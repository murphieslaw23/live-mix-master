import 'dart:async';

import 'audio_engine_bridge.dart';
import 'audio_permission_state.dart';
import 'native_audio_bindings.dart';

/// Non-real-time Dart host adapter for the native LiveMixMaster engine.
///
/// The native audio callback never crosses into Dart. This adapter performs
/// control calls and bounded status polling only.
class NativeAudioEngine implements AudioEngine {
  NativeAudioEngine({
    required this.bindings,
    required this.permissionState,
    this.pollInterval = const Duration(milliseconds: 33),
    this.noSignalPollThreshold = 2,
  }) : assert(noSignalPollThreshold > 0);

  final NativeAudioBindings bindings;
  final AudioPermissionState permissionState;
  final Duration? pollInterval;
  final int noSignalPollThreshold;

  final StreamController<List<ChannelMeterSnapshot>> _channelMeters =
      StreamController<List<ChannelMeterSnapshot>>.broadcast();
  final StreamController<MasterMeterSnapshot> _masterMeters =
      StreamController<MasterMeterSnapshot>.broadcast();
  final StreamController<TrackMatch> _trackMatches =
      StreamController<TrackMatch>.broadcast();

  final Map<String, InputChannelConfig> _channels =
      <String, InputChannelConfig>{};
  List<AudioInputEndpoint> _inputs = const <AudioInputEndpoint>[];
  Timer? _pollTimer;
  EngineState _state = EngineState.idle;
  AudioRouteState _routeState = AudioRouteState.idle;
  NativeCaptureStatus? _captureStatus;
  int? _lastCallbackCount;
  int _lastXrunCount = 0;
  int _stagnantPolls = 0;
  bool _disposed = false;

  @override
  EngineState get state => _state;

  AudioRouteState get routeState => _routeState;
  NativeCaptureStatus? get captureStatus => _captureStatus;
  List<AudioInputEndpoint> get inputDevices => List.unmodifiable(_inputs);

  @override
  Stream<List<ChannelMeterSnapshot>> get channelMeters =>
      _channelMeters.stream;

  @override
  Stream<MasterMeterSnapshot> get masterMeters => _masterMeters.stream;

  @override
  Stream<TrackMatch> get trackMatches => _trackMatches.stream;

  @override
  Future<void> initialize({
    int sampleRate = 48000,
    int framesPerBuffer = 256,
  }) async {
    _ensureUsable();
    _state = EngineState.preparing;
    _routeState = AudioRouteState.preparing;

    if (!bindings.initialize(sampleRate, framesPerBuffer)) {
      _state = EngineState.failed;
      _routeState = AudioRouteState.failed;
      throw StateError('Native audio engine initialization failed.');
    }

    switch (permissionState) {
      case AudioPermissionState.granted:
        _state = EngineState.idle;
        _routeState = AudioRouteState.idle;
      case AudioPermissionState.denied:
      case AudioPermissionState.restricted:
        _state = EngineState.degraded;
        _routeState = AudioRouteState.permissionDenied;
      case AudioPermissionState.unavailable:
        _state = EngineState.failed;
        _routeState = AudioRouteState.failed;
      case AudioPermissionState.unknown:
        _state = EngineState.idle;
        _routeState = AudioRouteState.idle;
    }

    if (pollInterval case final interval?) {
      _pollTimer = Timer.periodic(interval, (_) {
        if (!_disposed) {
          pollNow();
        }
      });
    }
  }

  Future<List<AudioInputEndpoint>> refreshInputDevices() async {
    _ensureUsable();
    final records = bindings.listInputDevices();
    _inputs = List<AudioInputEndpoint>.unmodifiable(
      records.map(
        (device) => AudioInputEndpoint(
          uid: device.uid,
          name: device.name,
          inputChannels: device.inputChannels,
          nominalSampleRate: device.nominalSampleRate,
          bufferFrames: device.bufferFrames,
        ),
      ),
    );

    if (_inputs.isEmpty && permissionState.canCapture) {
      _state = EngineState.degraded;
      _routeState = AudioRouteState.noDevice;
    } else if (_inputs.isNotEmpty &&
        permissionState.canCapture &&
        _channels.isEmpty) {
      _state = EngineState.idle;
      _routeState = AudioRouteState.idle;
    }
    return inputDevices;
  }

  @override
  Future<void> addChannel(InputChannelConfig channel) async {
    _ensureUsable();
    if (!permissionState.canCapture) {
      _state = EngineState.degraded;
      _routeState = AudioRouteState.permissionDenied;
      throw StateError('Audio input permission is not granted.');
    }
    if (!_inputs.any((input) => input.uid == channel.endpointId)) {
      _state = EngineState.degraded;
      _routeState = AudioRouteState.noDevice;
      throw StateError('Selected audio endpoint is not available.');
    }

    _state = EngineState.preparing;
    _routeState = AudioRouteState.preparing;

    final configured = bindings.addChannel(channel.id) &&
        bindings.setFader(channel.id, channel.fader) &&
        bindings.setMuted(channel.id, channel.muted) &&
        bindings.setSolo(channel.id, channel.solo) &&
        bindings.bindCaptureChannel(channel.id) &&
        bindings.captureStart(channel.endpointId);
    if (!configured) {
      _state = EngineState.failed;
      _routeState = AudioRouteState.failed;
      throw StateError('Native capture route configuration failed.');
    }

    _channels[channel.id] = channel;
    _lastCallbackCount = null;
    _lastXrunCount = 0;
    _stagnantPolls = 0;
  }

  @override
  Future<void> removeChannel(String channelId) async {
    _ensureUsable();
    if (!bindings.removeChannel(channelId)) {
      throw StateError('Native channel removal failed for $channelId.');
    }
    _channels.remove(channelId);
    if (_channels.isEmpty) {
      bindings.captureStop();
      _captureStatus = null;
      _lastCallbackCount = null;
      _lastXrunCount = 0;
      _stagnantPolls = 0;
      _state = EngineState.idle;
      _routeState = AudioRouteState.idle;
    }
  }

  @override
  Future<void> setFader(String channelId, double value) async {
    _ensureUsable();
    if (!bindings.setFader(channelId, value)) {
      throw StateError('Native fader update failed for $channelId.');
    }
  }

  @override
  Future<void> setMute(String channelId, bool value) async {
    _ensureUsable();
    if (!bindings.setMuted(channelId, value)) {
      throw StateError('Native mute update failed for $channelId.');
    }
  }

  @override
  Future<void> setSolo(String channelId, bool value) async {
    _ensureUsable();
    if (!bindings.setSolo(channelId, value)) {
      throw StateError('Native solo update failed for $channelId.');
    }
  }

  @override
  Future<void> setTrim(String channelId, double db) => Future<void>.error(
        UnsupportedError(
          'Native trim control is not part of the current C ABI yet.',
        ),
      );

  @override
  Future<void> setMasterGain(double db) => Future<void>.error(
        UnsupportedError(
          'Native master gain control is not part of the current C ABI yet.',
        ),
      );

  @override
  Future<void> startRecording(String filePath) => Future<void>.error(
        UnsupportedError(
          'Recording is owned by the non-real-time recording service boundary.',
        ),
      );

  @override
  Future<void> stopRecording() => Future<void>.error(
        UnsupportedError(
          'Recording is owned by the non-real-time recording service boundary.',
        ),
      );

  @override
  Future<void> startBroadcast(BroadcastTarget target) => Future<void>.error(
        UnsupportedError(
          'Broadcast delivery is owned by the broadcast service boundary.',
        ),
      );

  @override
  Future<void> stopBroadcast() => Future<void>.error(
        UnsupportedError(
          'Broadcast delivery is owned by the broadcast service boundary.',
        ),
      );

  /// Polls native lifecycle telemetry from the non-real-time host side.
  Future<void> pollNow() async {
    _ensureUsable();
    final status = bindings.captureStatus();
    final previousRoute = _routeState;
    final previousCallbacks = _lastCallbackCount;
    final previousXruns = _lastXrunCount;
    _captureStatus = status;

    switch (status.state) {
      case NativeCaptureState.idle:
        _state = EngineState.idle;
        _routeState = AudioRouteState.idle;
        _stagnantPolls = 0;
      case NativeCaptureState.starting:
        _state = EngineState.preparing;
        _routeState = AudioRouteState.preparing;
        _stagnantPolls = 0;
      case NativeCaptureState.deviceRemoved:
        _state = EngineState.degraded;
        _routeState = AudioRouteState.deviceLost;
        _stagnantPolls = 0;
      case NativeCaptureState.formatChanged:
        _state = EngineState.degraded;
        _routeState = AudioRouteState.formatError;
        _stagnantPolls = 0;
      case NativeCaptureState.failed:
        _state = EngineState.failed;
        _routeState = AudioRouteState.failed;
        _stagnantPolls = 0;
      case NativeCaptureState.running:
        final xrunAdvanced = status.xrunCount > previousXruns;
        final callbacksAdvanced = previousCallbacks == null ||
            status.callbackCount > previousCallbacks;

        if (xrunAdvanced) {
          _state = EngineState.degraded;
          _routeState = AudioRouteState.overrun;
          _stagnantPolls = 0;
        } else if (callbacksAdvanced) {
          _state = EngineState.running;
          _stagnantPolls = 0;
          _routeState = _requiresRecoveryPulse(previousRoute)
              ? AudioRouteState.recovered
              : AudioRouteState.active;
        } else {
          _stagnantPolls += 1;
          final threshold = previousRoute == AudioRouteState.recovered
              ? 1
              : noSignalPollThreshold;
          if (_stagnantPolls >= threshold) {
            _state = EngineState.degraded;
            _routeState = AudioRouteState.noSignal;
          } else {
            _state = EngineState.running;
            _routeState = AudioRouteState.active;
          }
        }
    }

    _lastCallbackCount = status.callbackCount;
    _lastXrunCount = status.xrunCount;
  }

  static bool _requiresRecoveryPulse(AudioRouteState state) => switch (state) {
        AudioRouteState.noSignal ||
        AudioRouteState.deviceLost ||
        AudioRouteState.formatError ||
        AudioRouteState.overrun ||
        AudioRouteState.failed =>
          true,
        _ => false,
      };

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _pollTimer?.cancel();
    bindings.captureStop();
    _disposed = true;
    await _channelMeters.close();
    await _masterMeters.close();
    await _trackMatches.close();
  }

  void _ensureUsable() {
    if (_disposed) {
      throw StateError('NativeAudioEngine has already been disposed.');
    }
  }
}
