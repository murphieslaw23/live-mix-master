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

    test('same-process Flutter runtime exposes non-secret acceptance telemetry', () {
      final telemetryFile = File('lib/audio/native_acceptance_telemetry.dart');
      final panelFile =
          File('lib/features/mixer/native_acceptance_telemetry_panel.dart');
      final main = File('lib/main.dart').readAsStringSync();
      final guide = File('docs/audio/macos-device-e2e.md').readAsStringSync();

      expect(telemetryFile.existsSync(), isTrue);
      expect(panelFile.existsSync(), isTrue);
      final telemetry = telemetryFile.existsSync()
          ? telemetryFile.readAsStringSync()
          : '';
      final panel = panelFile.existsSync() ? panelFile.readAsStringSync() : '';

      expect(telemetry, contains('AcceptanceTelemetrySnapshot'));
      expect(telemetry, contains('callbackCount'));
      expect(telemetry, contains('averageCallbackUs'));
      expect(telemetry, contains('maxCallbackUs'));
      expect(telemetry, contains('xrunCount'));
      expect(telemetry, contains('recorderQueueDepth'));
      expect(telemetry, contains('fingerprintQueueDepth'));
      expect(telemetry, contains('recorderRejectedBlocks'));
      expect(telemetry, contains('fingerprintRejectedBlocks'));
      expect(telemetry, contains('NativeAudioEngine'));
      expect(telemetry, contains('NativePcmRuntimePump'));

      expect(main, contains('NativeRuntimeAcceptanceTelemetry'));
      expect(main, contains('NativeAcceptanceTelemetryPanel'));
      expect(main, contains('telemetrySource:'));

      expect(panel, contains('E2E TELEMETRY'));
      expect(panel, contains('CALLBACKS'));
      expect(panel, contains('AVG CALLBACK'));
      expect(panel, contains('MAX CALLBACK'));
      expect(panel, contains('XRUNS'));
      expect(panel, contains('REC REJECT'));
      expect(panel, contains('FP REJECT'));

      expect(guide, contains('E2E TELEMETRY'));
      expect(guide, contains('same Flutter app process'));
    });
  });
}
