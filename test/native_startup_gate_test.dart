import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/audio_engine_bridge.dart';
import 'package:live_mix_master/audio/native_library_loader.dart';
import 'package:live_mix_master/features/mixer/mixer_desk_view.dart';
import 'package:live_mix_master/main.dart';

void main() {
  testWidgets('native engine failure blocks mixer with actionable recovery', (tester) async {
    final unavailable = NativeLibraryLoadResult.failure(
      searchedPaths: const [
        '/workspace/live-mix-master/build/native/liblive_mixer_engine.dylib',
        '/Applications/LiveMixMaster.app/Contents/Frameworks/liblive_mixer_engine.dylib',
      ],
    );

    await tester.pumpWidget(
      LiveMixMasterApp(nativeLibraryResult: unavailable),
    );
    await tester.pumpAndSettle();

    expect(find.text('NATIVE ENGINE UNAVAILABLE'), findsOneWidget);
    expect(find.textContaining('LMM_NATIVE_LIBRARY'), findsOneWidget);
    expect(
      find.textContaining('cmake -S native -B build/native'),
      findsOneWidget,
    );
    expect(find.byType(MixerDeskView), findsNothing);
  });

  testWidgets('loaded native runtime injects prepared engine into mixer', (tester) async {
    final engine = _FakeAudioEngine();
    final loaded = NativeLibraryLoadResult.loaded(
      library: DynamicLibrary.process(),
      path: 'process',
      searchedPaths: const ['process'],
    );

    await tester.pumpWidget(
      LiveMixMasterApp(
        nativeLibraryResult: loaded,
        audioEngineFuture: Future<AudioEngine>.value(engine),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MixerDeskView), findsOneWidget);
    final mixer = tester.widget<MixerDeskView>(find.byType(MixerDeskView));
    expect(mixer.audioEngine, same(engine));
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
  Future<List<AudioInputEndpoint>> refreshInputDevices() async =>
      const <AudioInputEndpoint>[];

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
