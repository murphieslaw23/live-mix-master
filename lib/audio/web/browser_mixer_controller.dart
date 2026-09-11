import 'dart:async';

import 'browser_mixer_protocol.dart';

abstract interface class BrowserMixerGateway {
  Stream<BrowserMixerTelemetry> get telemetry;

  Future<void> configure(BrowserMixerConfiguration configuration);
}

typedef BrowserMixerStateListener = void Function(BrowserMixerState state);

class BrowserMixerState {
  const BrowserMixerState({
    required this.enabled,
    required this.fader,
    required this.muted,
    required this.solo,
    required this.masterPeakLeft,
    required this.masterPeakRight,
    required this.limiterActive,
    this.activeChannelId,
    this.channelMeter,
  });

  const BrowserMixerState.disabled()
      : enabled = false,
        activeChannelId = null,
        fader = 1,
        muted = false,
        solo = false,
        channelMeter = null,
        masterPeakLeft = 0,
        masterPeakRight = 0,
        limiterActive = false;

  final bool enabled;
  final String? activeChannelId;
  final double fader;
  final bool muted;
  final bool solo;
  final BrowserChannelMeter? channelMeter;
  final double masterPeakLeft;
  final double masterPeakRight;
  final bool limiterActive;
}

class BrowserMixerController {
  BrowserMixerController({required BrowserMixerGateway gateway})
      : _gateway = gateway {
    _telemetrySubscription = _gateway.telemetry.listen(_handleTelemetry);
  }

  static const double _linearTrim = 1;
  static const double _masterGainLinear = 1;
  static const int _telemetryEvery = 20;

  final BrowserMixerGateway _gateway;
  final Set<BrowserMixerStateListener> _listeners =
      <BrowserMixerStateListener>{};
  late final StreamSubscription<BrowserMixerTelemetry> _telemetrySubscription;

  BrowserMixerState _state = const BrowserMixerState.disabled();
  BrowserMixerConfiguration? _pendingConfiguration;
  Future<void> _configurationDrain = Future<void>.value();
  bool _configurationDrainRunning = false;
  bool _disposed = false;

  BrowserMixerState get state => _state;

  void addListener(BrowserMixerStateListener listener) {
    if (!_disposed) {
      _listeners.add(listener);
    }
  }

  void removeListener(BrowserMixerStateListener listener) {
    _listeners.remove(listener);
  }

  Future<void> attach(String channelId) {
    _ensureNotDisposed();
    final normalizedId = channelId.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError.value(channelId, 'channelId', 'must not be empty');
    }
    _setState(
      BrowserMixerState(
        enabled: true,
        activeChannelId: normalizedId,
        fader: 1,
        muted: false,
        solo: false,
        channelMeter: null,
        masterPeakLeft: 0,
        masterPeakRight: 0,
        limiterActive: false,
      ),
    );
    return _queueConfiguration();
  }

  Future<void> setFader(double value) {
    _ensureNotDisposed();
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'value', 'must be finite');
    }
    if (!_state.enabled) {
      return Future<void>.value();
    }
    final normalized = value.clamp(0.0, 1.0).toDouble();
    _setState(
      BrowserMixerState(
        enabled: true,
        activeChannelId: _state.activeChannelId,
        fader: normalized,
        muted: _state.muted,
        solo: _state.solo,
        channelMeter: _state.channelMeter,
        masterPeakLeft: _state.masterPeakLeft,
        masterPeakRight: _state.masterPeakRight,
        limiterActive: _state.limiterActive,
      ),
    );
    return _queueConfiguration();
  }

  Future<void> setMuted(bool value) {
    _ensureNotDisposed();
    if (!_state.enabled) {
      return Future<void>.value();
    }
    _setState(
      BrowserMixerState(
        enabled: true,
        activeChannelId: _state.activeChannelId,
        fader: _state.fader,
        muted: value,
        solo: _state.solo,
        channelMeter: _state.channelMeter,
        masterPeakLeft: _state.masterPeakLeft,
        masterPeakRight: _state.masterPeakRight,
        limiterActive: _state.limiterActive,
      ),
    );
    return _queueConfiguration();
  }

  Future<void> setSolo(bool value) {
    _ensureNotDisposed();
    if (!_state.enabled) {
      return Future<void>.value();
    }
    _setState(
      BrowserMixerState(
        enabled: true,
        activeChannelId: _state.activeChannelId,
        fader: _state.fader,
        muted: _state.muted,
        solo: value,
        channelMeter: _state.channelMeter,
        masterPeakLeft: _state.masterPeakLeft,
        masterPeakRight: _state.masterPeakRight,
        limiterActive: _state.limiterActive,
      ),
    );
    return _queueConfiguration();
  }

  Future<void> detach() {
    _ensureNotDisposed();
    _pendingConfiguration = null;
    _setState(const BrowserMixerState.disabled());
    return _configurationDrain;
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _pendingConfiguration = null;
    await _configurationDrain;
    await _telemetrySubscription.cancel();
    _listeners.clear();
  }

  Future<void> _queueConfiguration() {
    final channelId = _state.activeChannelId;
    if (!_state.enabled || channelId == null) {
      return _configurationDrain;
    }

    _pendingConfiguration = BrowserMixerConfiguration(
      masterGainLinear: _masterGainLinear,
      telemetryEvery: _telemetryEvery,
      channels: <BrowserMixerChannelConfiguration>[
        BrowserMixerChannelConfiguration(
          id: channelId,
          linearTrim: _linearTrim,
          fader: _state.fader,
          muted: _state.muted,
          solo: _state.solo,
        ),
      ],
    );

    if (_configurationDrainRunning) {
      return _configurationDrain;
    }

    final completer = Completer<void>();
    _configurationDrain = completer.future;
    _configurationDrainRunning = true;

    () async {
      try {
        while (_pendingConfiguration != null && !_disposed) {
          final configuration = _pendingConfiguration!;
          _pendingConfiguration = null;
          await _gateway.configure(configuration);
        }
        completer.complete();
      } on Object catch (error, stackTrace) {
        _pendingConfiguration = null;
        completer.completeError(error, stackTrace);
      } finally {
        _configurationDrainRunning = false;
      }
    }();

    return _configurationDrain;
  }

  void _handleTelemetry(BrowserMixerTelemetry telemetry) {
    if (_disposed || !_state.enabled) {
      return;
    }
    final channelId = _state.activeChannelId;
    if (channelId == null) {
      return;
    }
    final meter = telemetry.channelMeters[channelId];
    _setState(
      BrowserMixerState(
        enabled: true,
        activeChannelId: channelId,
        fader: _state.fader,
        muted: _state.muted,
        solo: _state.solo,
        channelMeter: meter ?? _state.channelMeter,
        masterPeakLeft: telemetry.masterPeakLeft,
        masterPeakRight: telemetry.masterPeakRight,
        limiterActive: telemetry.limiterActive,
      ),
    );
  }

  void _setState(BrowserMixerState state) {
    _state = state;
    for (final listener in List<BrowserMixerStateListener>.of(_listeners)) {
      listener(state);
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('BrowserMixerController is disposed');
    }
  }
}
