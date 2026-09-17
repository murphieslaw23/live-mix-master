import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/native_library_loader.dart';

void main() {
  group('NativeLibraryLoader', () {
    test('orders override, repo debug build, then app bundle Frameworks', () {
      final candidates = NativeLibraryLoader.candidatePaths(
        environment: const {
          'LMM_NATIVE_LIBRARY': '/custom/liblive_mixer_engine.dylib',
        },
        currentDirectory: '/workspace/live-mix-master',
        resolvedExecutable:
            '/workspace/live-mix-master/build/macos/Build/Products/Debug/live_mix_master.app/Contents/MacOS/live_mix_master',
        operatingSystem: 'macos',
      );

      expect(
        candidates,
        const [
          '/custom/liblive_mixer_engine.dylib',
          '/workspace/live-mix-master/build/native/liblive_mixer_engine.dylib',
          '/workspace/live-mix-master/build/macos/Build/Products/Debug/live_mix_master.app/Contents/Frameworks/liblive_mixer_engine.dylib',
        ],
      );
    });

    test('orders Linux override, repo debug build, then bundled shared object', () {
      final candidates = NativeLibraryLoader.candidatePaths(
        environment: const {
          'LMM_NATIVE_LIBRARY': '/custom/liblive_mixer_engine.so',
        },
        currentDirectory: '/workspace/live-mix-master',
        resolvedExecutable:
            '/workspace/live-mix-master/build/linux/x64/debug/bundle/live_mix_master',
        operatingSystem: 'linux',
      );

      expect(
        candidates,
        const [
          '/custom/liblive_mixer_engine.so',
          '/workspace/live-mix-master/build/native/liblive_mixer_engine.so',
          '/workspace/live-mix-master/build/linux/x64/debug/bundle/lib/liblive_mixer_engine.so',
        ],
      );
    });

    test('missing library returns actionable recovery guidance', () {
      final result = NativeLibraryLoader.tryLoad(
        environment: const {},
        currentDirectory: '/workspace/live-mix-master',
        resolvedExecutable:
            '/Applications/LiveMixMaster.app/Contents/MacOS/live_mix_master',
        operatingSystem: 'macos',
        fileExists: (_) => false,
      );

      expect(result.isLoaded, isFalse);
      expect(result.loadedPath, isNull);
      expect(result.message, contains('NATIVE ENGINE UNAVAILABLE'));
      expect(result.message, contains('LMM_NATIVE_LIBRARY'));
      expect(
        result.message,
        contains('cmake -S native -B build/native -DCMAKE_BUILD_TYPE=Debug'),
      );
      expect(
        result.searchedPaths,
        contains('/workspace/live-mix-master/build/native/liblive_mixer_engine.dylib'),
      );
      expect(
        result.searchedPaths,
        contains(
          '/Applications/LiveMixMaster.app/Contents/Frameworks/liblive_mixer_engine.dylib',
        ),
      );
    });
  });
}
