import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/audio_engine_port.dart';
import 'package:live_mix_master/features/mixer/mixer_desk_view.dart';
import 'package:live_mix_master/main.dart';

void main() {
  testWidgets('desktop audio engine failure blocks mixer with actionable recovery', (tester) async {
    const unavailable = AudioEngineBootstrapResult.unavailable(
      kind: AudioEngineKind.desktopNative,
      message: 'NATIVE ENGINE UNAVAILABLE\n'
          'Build the debug engine with:\n'
          'cmake -S native -B build/native -DCMAKE_BUILD_TYPE=Debug\n'
          'Then restart LiveMixMaster. You can override the library path with LMM_NATIVE_LIBRARY.',
      diagnostics: [
        '/workspace/live-mix-master/build/native/liblive_mixer_engine.dylib',
        '/Applications/LiveMixMaster.app/Contents/Frameworks/liblive_mixer_engine.dylib',
      ],
    );

    await tester.pumpWidget(
      const LiveMixMasterApp(audioEngineResult: unavailable),
    );
    await tester.pumpAndSettle();

    expect(find.text('AUDIO ENGINE UNAVAILABLE'), findsOneWidget);
    expect(find.textContaining('NATIVE ENGINE UNAVAILABLE'), findsOneWidget);
    expect(find.textContaining('LMM_NATIVE_LIBRARY'), findsOneWidget);
    expect(
      find.textContaining('cmake -S native -B build/native'),
      findsOneWidget,
    );
    expect(find.byType(MixerDeskView), findsNothing);
  });
}
