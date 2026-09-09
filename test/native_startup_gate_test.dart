import 'package:flutter_test/flutter_test.dart';
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
}
