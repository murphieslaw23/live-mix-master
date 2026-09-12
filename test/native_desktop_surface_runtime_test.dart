import 'dart:async';
import 'dart:ffi';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/app/app_surface_desktop.dart';
import 'package:live_mix_master/audio/audio_engine_bridge.dart';
import 'package:live_mix_master/audio/audio_engine_factory_desktop.dart';
import 'package:live_mix_master/audio/native_desktop_runtime.dart';
import 'package:live_mix_master/audio/native_library_loader.dart';
import 'package:live_mix_master/features/mixer/mixer_desk_view.dart';

void main() {
  testWidgets('desktop surface prepares runtime and injects native engine', (tester) async {
    final nativeEngine = _FakeAudioEngine();
    final runtime = NativeDesktopRuntime.testing(audioEngine: nativeEngine);
    final port = DesktopNativeAudioEngine(
      loadNativeLibrary: () => NativeLibraryLoadResult.loaded(
        library: DynamicLibrary.process(),
        path: '/tmp/liblive_mixer_engine.dylib',
        searchedPaths: const ['/tmp/liblive_mixer_engine.dylib'],
      ),
      runtimeBuilder: (_) async => runtime,
    );

    expect(port.initialize().isAvailable, isTrue);

    await tester.pumpWidget(
      MaterialApp(home: buildPrimaryOperatorSurface(port)),
    );
    await tester.pumpAndSettle();

    final mixer = tester.widget<MixerDeskView>(find.byType(MixerDeskView));
    expect(mixer.audioEngine, same(nativeEngine));
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
