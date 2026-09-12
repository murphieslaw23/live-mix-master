import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/audio_engine_factory_desktop.dart';
import 'package:live_mix_master/audio/native_desktop_runtime.dart';
import 'package:live_mix_master/audio/native_library_loader.dart';

void main() {
  test('desktop factory exposes runtime preparation after bootstrap', () async {
    final fakeRuntime = NativeDesktopRuntime.testing();
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
