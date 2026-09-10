import 'audio_engine_port.dart';
import 'native_library_loader.dart';

class DesktopNativeAudioEngine implements AudioEnginePort {
  DesktopNativeAudioEngine({
    NativeLibraryLoadResult Function()? loadNativeLibrary,
  }) : _loadNativeLibrary = loadNativeLibrary ?? NativeLibraryLoader.tryLoad;

  final NativeLibraryLoadResult Function() _loadNativeLibrary;

  NativeLibraryLoadResult? _nativeLibraryResult;

  NativeLibraryLoadResult? get nativeLibraryResult => _nativeLibraryResult;

  @override
  AudioEngineKind get kind => AudioEngineKind.desktopNative;

  @override
  AudioEngineBootstrapResult initialize() {
    final result = _loadNativeLibrary();
    _nativeLibraryResult = result;

    if (result.isLoaded) {
      return AudioEngineBootstrapResult.available(
        kind: kind,
        message: result.message,
        diagnostics: result.loadedPath == null ? const [] : [result.loadedPath!],
      );
    }

    return AudioEngineBootstrapResult.unavailable(
      kind: kind,
      message: result.message,
      diagnostics: result.searchedPaths,
    );
  }
}

AudioEnginePort createAudioEnginePort() => DesktopNativeAudioEngine();
