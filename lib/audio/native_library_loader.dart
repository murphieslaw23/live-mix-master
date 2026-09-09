import 'dart:ffi';
import 'dart:io';

class NativeLibraryLoadResult {
  const NativeLibraryLoadResult._({
    required this.library,
    required this.loadedPath,
    required this.searchedPaths,
    required this.message,
  });

  factory NativeLibraryLoadResult.loaded({
    required DynamicLibrary library,
    required String path,
    required List<String> searchedPaths,
  }) {
    return NativeLibraryLoadResult._(
      library: library,
      loadedPath: path,
      searchedPaths: List.unmodifiable(searchedPaths),
      message: 'Native engine loaded from $path',
    );
  }

  factory NativeLibraryLoadResult.failure({
    required List<String> searchedPaths,
    String? loaderError,
  }) {
    final detail = loaderError == null || loaderError.isEmpty
        ? ''
        : '\nLoader detail: $loaderError';
    return NativeLibraryLoadResult._(
      library: null,
      loadedPath: null,
      searchedPaths: List.unmodifiable(searchedPaths),
      message: 'NATIVE ENGINE UNAVAILABLE\n'
          'Build the debug engine with:\n'
          'cmake -S native -B build/native -DCMAKE_BUILD_TYPE=Debug\n'
          'cmake --build build/native --config Debug --parallel\n'
          'Then restart LiveMixMaster. You can override the library path with '
          'LMM_NATIVE_LIBRARY.$detail',
    );
  }

  final DynamicLibrary? library;
  final String? loadedPath;
  final List<String> searchedPaths;
  final String message;

  bool get isLoaded => library != null;
}

class NativeLibraryLoader {
  static const String libraryFileName = 'liblive_mixer_engine.dylib';

  static List<String> candidatePaths({
    required Map<String, String> environment,
    required String currentDirectory,
    required String resolvedExecutable,
  }) {
    final candidates = <String>[];
    final override = environment['LMM_NATIVE_LIBRARY']?.trim();
    if (override != null && override.isNotEmpty) {
      candidates.add(override);
    }

    candidates.add(_join(currentDirectory, 'build/native/$libraryFileName'));

    final bundleContents = _bundleContentsDirectory(resolvedExecutable);
    if (bundleContents != null) {
      candidates.add(_join(bundleContents, 'Frameworks/$libraryFileName'));
    }

    return List.unmodifiable(candidates.toSet());
  }

  static NativeLibraryLoadResult tryLoad({
    Map<String, String>? environment,
    String? currentDirectory,
    String? resolvedExecutable,
    bool Function(String path)? fileExists,
    DynamicLibrary Function(String path)? openLibrary,
  }) {
    final paths = candidatePaths(
      environment: environment ?? Platform.environment,
      currentDirectory: currentDirectory ?? Directory.current.path,
      resolvedExecutable: resolvedExecutable ?? Platform.resolvedExecutable,
    );
    final exists = fileExists ?? (path) => File(path).existsSync();
    final open = openLibrary ?? DynamicLibrary.open;
    String? lastLoaderError;

    for (final path in paths) {
      if (!exists(path)) continue;
      try {
        return NativeLibraryLoadResult.loaded(
          library: open(path),
          path: path,
          searchedPaths: paths,
        );
      } on Object catch (error) {
        lastLoaderError = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      }
    }

    return NativeLibraryLoadResult.failure(
      searchedPaths: paths,
      loaderError: lastLoaderError,
    );
  }

  static String? _bundleContentsDirectory(String resolvedExecutable) {
    final normalized = resolvedExecutable.replaceAll('\\', '/');
    const marker = '/Contents/MacOS/';
    final markerIndex = normalized.lastIndexOf(marker);
    if (markerIndex < 0) return null;
    return '${normalized.substring(0, markerIndex)}/Contents';
  }

  static String _join(String base, String suffix) {
    final normalizedBase = base.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
    return '$normalizedBase/$suffix';
  }
}
