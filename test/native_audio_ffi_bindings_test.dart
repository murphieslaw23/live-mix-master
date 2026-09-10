import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/native_audio_bindings.dart';
import 'package:live_mix_master/audio/native_audio_ffi_bindings.dart';

void main() {
  final nativeLibraryPath = Platform.environment['LMM_NATIVE_LIBRARY'];
  final skipReason = nativeLibraryPath == null || nativeLibraryPath.isEmpty
      ? 'requires a built native engine via LMM_NATIVE_LIBRARY'
      : false;

  test(
    'DynamicLibrary bindings cover device control capture and meter ABI',
    () {
      final path = Platform.environment['LMM_NATIVE_LIBRARY'];
      if (path == null || path.isEmpty) {
        fail('LMM_NATIVE_LIBRARY must point at the built test dylib.');
      }

      final bindings = FfiNativeAudioBindings(DynamicLibrary.open(path));

      expect(bindings.initialize(48000, 256), isTrue);

      final devices = bindings.listInputDevices();
      for (final device in devices) {
        expect(device.uid, isNotEmpty);
        expect(device.name, isNotEmpty);
        expect(device.inputChannels, greaterThan(0));
        expect(device.nominalSampleRate, greaterThan(0));
        expect(device.bufferFrames, greaterThan(0));
      }

      const channelId = 'dart-ffi-smoke';
      expect(bindings.addChannel(channelId), isTrue);
      expect(bindings.setFader(channelId, .5), isTrue);
      expect(bindings.setMuted(channelId, true), isTrue);
      expect(bindings.setSolo(channelId, false), isTrue);
      expect(bindings.bindCaptureChannel(channelId), isTrue);

      final channelMeter = bindings.channelMeter(channelId);
      expect(channelMeter, isNotNull);
      expect(channelMeter!.peakLeft, 0);
      expect(channelMeter.peakRight, 0);
      expect(channelMeter.rmsLeft, 0);
      expect(channelMeter.rmsRight, 0);
      expect(channelMeter.clipping, isFalse);

      final masterMeter = bindings.masterMeter();
      expect(masterMeter, isNotNull);
      expect(masterMeter!.truePeakLeft, 0);
      expect(masterMeter.truePeakRight, 0);
      expect(masterMeter.limiterActive, isFalse);

      expect(bindings.captureStatus().state, NativeCaptureState.idle);
      expect(bindings.captureStart('__lmm_invalid_device_uid__'), isFalse);
      expect(bindings.captureStatus().state, NativeCaptureState.failed);
      bindings.captureStop();
      expect(bindings.captureStatus().state, NativeCaptureState.idle);

      expect(bindings.removeChannel(channelId), isTrue);
    },
    skip: skipReason,
  );
}
