import 'dart:ffi';

import 'audio_engine_port.dart';
import 'native_desktop_runtime.dart';
import 'native_library_loader.dart';

class DesktopNativeAudioEngine implements AudioEnginePort {
  DesktopNativeAudioEngine({
    NativeLibraryLoadResult Function()? loadNativeLibrary,
    Future<NativeDesktopRuntime> Function(DynamicLibrary)? runtimeBuilder,
  })  : _loadNativeLibrary = loadNativeLibrary ?? NativeLibraryLoader.tryLoad,
        _runtimeBuilder = runtimeBuilder ?? NativeDesktopRuntime.create;

  final NativeLibraryLoadResult Function() _loadNativeLibrary;
  final Future<NativeDesktopRuntime> Function(DynamicLibrary) _runtimeBuilder;

  NativeLibraryLoadResult? _nativeLibraryResult;
  Future<NativeDesktopRuntime>? _runtimeFuture;

  NativeLibraryLoadResult? get nativeLibraryResult => _nativeLibraryResult;

  @override
  AudioEngineKind get kind => AudioEngineKind.desktopNative;

  @override
  AudioEngineBootstrapResult initialize() {
    final result = _loadNativeLibrary();
    _nativeLibraryResult = result;
    _runtimeFuture = null;

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

  Future<NativeDesktopRuntime> prepareRuntime() {
    final existing = _runtimeFuture;
    if (existing != null) return existing;

    final library = _nativeLibraryResult?.library;
    if (library == null) {
      return Future<NativeDesktopRuntime>.error(
        StateError('Native library is not loaded.'),
      );
    }

    final future = _runtimeBuilder(library);
    _runtimeFuture = future;
    return future;
  }
}

AudioEnginePort createAudioEnginePort() => DesktopNativeAudioEngine();
