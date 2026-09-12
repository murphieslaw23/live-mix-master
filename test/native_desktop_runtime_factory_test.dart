import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/audio_engine_bridge.dart';
import 'package:live_mix_master/audio/audio_engine_factory_desktop.dart';
import 'package:live_mix_master/audio/native_desktop_runtime.dart';
import 'package:live_mix_master/audio/native_library_loader.dart';

void main() {
  test('desktop factory exposes runtime preparation after bootstrap', () async {
    final fakeRuntime = NativeDesktopRuntime.testing(audioEngine: _FakeAudioEngine());
    final engine = DesktopNativeAudioEngine(
      loadNativeLibrary: () => NativeLibraryLoadResult.loaded(
        library: DynamicLibrary.process(),
        path: '/tmp/liblive_mixer_engine.dylib',
        searchedPaths: const ['/tmp/liblive_mixer_engine.dylib'],
      ),
      runtimeBuilder: (_) async => fakeRuntime,
    );

    expect(engine.initialize().isAvailable, isTrue);
    expect(await engine.prepareRuntime(), same(fakeRuntime));
  });
}

class _FakeAudioEngine implements AudioEngine {
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
  Future<void> initialize({int sampleRate = 48000, int framesPerBuffer = 256}) async {}

  @override
  Future<List<AudioInputEndpoint>> refreshInputDevices() async => const [];

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
