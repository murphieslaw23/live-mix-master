import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/native_audio_ffi_bindings.dart';
import 'package:live_mix_master/audio/native_audio_gain_ffi.dart';
import 'package:live_mix_master/audio/native_audio_permission_bindings.dart';

void main() {
  final libraryPath = Platform.environment['LMM_NATIVE_LIBRARY']?.trim();
  final enabled = libraryPath != null && libraryPath.isNotEmpty;

  test(
    'built macOS dylib exposes the production control/status ABI',
    () {
      final library = DynamicLibrary.open(libraryPath!);
      final audio = FfiNativeAudioBindings(library);
      final gain = FfiNativeAudioGainBindings(library);
      final permissions = FfiAudioInputPermissionBindings(library);

      expect(audio.initialize(48000, 256), isTrue);
      expect(audio.listInputDevices(), isA<List>());
      expect(audio.captureStatus().state.name, 'idle');
      expect(permissions.readStatus().name, isNotEmpty);

      const channelId = 'ffi-smoke';
      expect(audio.addChannel(channelId), isTrue);
      expect(gain.setTrim(channelId, -3), isTrue);
      expect(audio.setFader(channelId, .75), isTrue);
      expect(audio.setMuted(channelId, true), isTrue);
      expect(audio.setSolo(channelId, false), isTrue);
      expect(gain.setMasterGain(-2), isTrue);
      expect(audio.removeChannel(channelId), isTrue);
    },
    skip: enabled ? false : 'LMM_NATIVE_LIBRARY is not set for this test run.',
  );
}
