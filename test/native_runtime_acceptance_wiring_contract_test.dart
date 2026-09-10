import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Issue #3 real-host runtime wiring contract', () {
    test('drains both native PCM queues into non-real-time consumers', () {
      final handoff = File('lib/audio/native_pcm_handoff_bindings.dart')
          .readAsStringSync();
      final ffi = File('lib/audio/native_audio_ffi_bindings.dart')
          .readAsStringSync();
      final main = File('lib/main.dart').readAsStringSync();
      final pump = File('lib/audio/native_pcm_runtime_pump.dart');

      expect(handoff, contains('popRecordingBlock'));
      expect(handoff, contains('popFingerprintBlock'));
      expect(ffi, contains('lmm_pop_recording_pcm'));
      expect(ffi, contains('lmm_pop_fingerprint_pcm'));
      expect(pump.existsSync(), isTrue);

      final pumpSource = pump.readAsStringSync();
      expect(pumpSource, contains('Timer.periodic'));
      expect(pumpSource, contains('popFingerprintBlock'));
      expect(pumpSource, contains('NativeRecordingDrain'));

      expect(main, contains('NativePcmRuntimePump'));
      expect(main, contains('LosslessRecordingWriter'));
      expect(main, contains('recordingWriter:'));
      expect(main, contains('fingerprintService:'));
    });

    test('mixer consumes native meters and does not present invented loudness', () {
      final mixer = File('lib/features/mixer/mixer_desk_view.dart')
          .readAsStringSync();

      expect(mixer, contains('channelMeters.listen'));
      expect(mixer, contains('masterMeters.listen'));
      expect(mixer, isNot(contains('channel.fader * .9')));
      expect(mixer, isNot(contains("'-14.2 LUFS'")));
      expect(mixer, isNot(contains("'-6.0 dBTP'")));
    });
  });
}
