import 'dart:ffi';

/// Application-scoped handle for the desktop native runtime.
///
/// Task 1 establishes the lifecycle seam without changing the visible desktop
/// surface. Task 2 attaches the Core Audio engine and capture services once the
/// required native symbols have been forward-ported onto current main.
class NativeDesktopRuntime {
  NativeDesktopRuntime._(this.library);

  final DynamicLibrary library;

  static Future<NativeDesktopRuntime> create(DynamicLibrary library) async {
    return NativeDesktopRuntime._(library);
  }

  factory NativeDesktopRuntime.testing() {
    return NativeDesktopRuntime._(DynamicLibrary.process());
  }
}
