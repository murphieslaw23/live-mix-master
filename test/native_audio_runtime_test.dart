import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/audio_engine_bridge.dart';
import 'package:live_mix_master/audio/audio_permission_state.dart';
import 'package:live_mix_master/audio/native_audio_permission_bindings.dart';
import 'package:live_mix_master/audio/native_audio_runtime.dart';

void main() {
  group('NativeAudioRuntime bootstrap contract', () {
    test('unknown permission is requested once before engine initialization', () async {
      final permissions = _FakePermissionBindings(
        initial: AudioPermissionState.unknown,
        afterRequest: AudioPermissionState.granted,
      );
      final engine = _FakeAudioEngine();
      AudioPermissionState? enginePermission;

      final runtime = NativeAudioRuntime(
        permissions: permissions,
        engineFactory: (permission) {
          enginePermission = permission;
          return engine;
        },
        pollDelay: (_) async {},
      );

      final prepared = await runtime.prepare();

      expect(prepared, same(engine));
      expect(permissions.requestCalls, 1);
      expect(enginePermission, AudioPermissionState.granted);
      expect(engine.initializeCalls, 1);
      expect(engine.refreshCalls, 1);
    });

    test('known denied permission is surfaced without requesting again', () async {
      final permissions = _FakePermissionBindings(
        initial: AudioPermissionState.denied,
      );
      final engine = _FakeAudioEngine();
      AudioPermissionState? enginePermission;

      final runtime = NativeAudioRuntime(
        permissions: permissions,
        engineFactory: (permission) {
          enginePermission = permission;
          return engine;
        },
      );

      await runtime.prepare();

      expect(permissions.requestCalls, 0);
      expect(enginePermission, AudioPermissionState.denied);
      expect(engine.initializeCalls, 1);
      expect(engine.refreshCalls, 1);
    });
  });
}

class _FakePermissionBindings implements AudioInputPermissionBindings {
  _FakePermissionBindings({
    required AudioPermissionState initial,
    this.afterRequest,
  }) : _state = initial;

  AudioPermissionState _state;
  final AudioPermissionState? afterRequest;
  int requestCalls = 0;

  @override
  AudioPermissionState readStatus() => _state;

  @override
  bool request() {
    requestCalls += 1;
    final next = afterRequest;
    if (next != null) _state = next;
    return true;
  }
}

class _FakeAudioEngine implements AudioEngine {
  int initializeCalls = 0;
  int refreshCalls = 0;

  @override
  EngineState get state => EngineState.idle;

  @override
  AudioRouteState get routeState => AudioRouteState.idle;

  @override
  Stream<AudioRouteState> get routeStates => const Stream.empty();

  @override
  Stream<List<ChannelMeterSnapshot>> get channelMeters => const Stream.empty();

  @override
  Stream<MasterMeterSnapshot> get masterMeters => const Stream.empty();

  @override
  Stream<TrackMatch> get trackMatches => const Stream.empty();

  @override
  Future<void> initialize({int sampleRate = 48000, int framesPerBuffer = 256}) async {
    initializeCalls += 1;
  }

  @override
  Future<List<AudioInputEndpoint>> refreshInputDevices() async {
    refreshCalls += 1;
    return const <AudioInputEndpoint>[];
  }

  @override
  Future<void> addChannel(InputChannelConfig channel) async {}

  @override
  Future<void> removeChannel(String channelId) async {}

  @override
  Future<void> setTrim(String channelId, double db) async {}

  @override
  Future<void> setFader(String channelId, double value) async {}

  @override
  Future<void> setMute(String channelId, bool value) async {}

  @override
  Future<void> setSolo(String channelId, bool value) async {}

  @override
  Future<void> setMasterGain(double db) async {}

  @override
  Future<void> startRecording(String filePath) async {}

  @override
  Future<void> stopRecording() async {}

  @override
  Future<void> startBroadcast(BroadcastTarget target) async {}

  @override
  Future<void> stopBroadcast() async {}

  @override
  Future<void> dispose() async {}
}
