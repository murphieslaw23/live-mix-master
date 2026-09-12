import 'dart:ffi';

import 'audio_engine_bridge.dart';
import 'native_audio_engine.dart';
import 'native_audio_ffi_bindings.dart';
import 'native_audio_permission_bindings.dart';
import 'native_audio_runtime.dart';

/// Application-scoped owner for the desktop native audio runtime.
///
/// Native callbacks stay entirely in C/C++. This object owns only the
/// non-real-time Dart control adapter and prepares it from the dylib loaded by
/// the current platform factory.
class NativeDesktopRuntime {
  NativeDesktopRuntime._({
    required this.library,
    required this.audioEngine,
  });

  final DynamicLibrary library;
  final AudioEngine audioEngine;

  static Future<NativeDesktopRuntime> create(DynamicLibrary library) async {
    final permissions = FfiAudioInputPermissionBindings(library);
    final bindings = FfiNativeAudioBindings(library);
    final runtime = NativeAudioRuntime(
      permissions: permissions,
      engineFactory: (permissionState) => NativeAudioEngine(
        bindings: bindings,
        permissionState: permissionState,
        permissionStateProvider: permissions.readStatus,
        requestPermission: permissions.request,
      ),
    );

    final engine = await runtime.prepare();
    return NativeDesktopRuntime._(
      library: library,
      audioEngine: engine,
    );
  }

  factory NativeDesktopRuntime.testing({required AudioEngine audioEngine}) {
    return NativeDesktopRuntime._(
      library: DynamicLibrary.process(),
      audioEngine: audioEngine,
    );
  }
}
