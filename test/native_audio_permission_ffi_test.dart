import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/audio_permission_state.dart';
import 'package:live_mix_master/audio/native_audio_permission_ffi.dart';

void main() {
  group('FfiAudioPermissionBindings', () {
    test('maps the native permission ABI exactly to the Dart vocabulary', () {
      expect(
        FfiAudioPermissionBindings.mapStatus(0),
        AudioPermissionState.unknown,
      );
      expect(
        FfiAudioPermissionBindings.mapStatus(1),
        AudioPermissionState.granted,
      );
      expect(
        FfiAudioPermissionBindings.mapStatus(2),
        AudioPermissionState.denied,
      );
      expect(
        FfiAudioPermissionBindings.mapStatus(3),
        AudioPermissionState.restricted,
      );
      expect(
        FfiAudioPermissionBindings.mapStatus(4),
        AudioPermissionState.unavailable,
      );
      expect(
        () => FfiAudioPermissionBindings.mapStatus(99),
        throwsStateError,
      );
    });

    test('reads status from the built native library without requesting consent', () {
      final path = Platform.environment['LMM_NATIVE_LIBRARY'];
      if (path == null || path.isEmpty) {
        markTestSkipped('requires a built native engine via LMM_NATIVE_LIBRARY');
      }

      final bindings = FfiAudioPermissionBindings(DynamicLibrary.open(path!));
      expect(AudioPermissionState.values, contains(bindings.status));
    });
  });
}
