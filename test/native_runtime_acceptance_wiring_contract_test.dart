import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Issue #3 native runtime wiring', () {
    test('capture status is negotiated before services are activated', () {
      final engine = File('lib/audio/native_audio_engine.dart').readAsStringSync();
      final captureStart = engine.indexOf('bindings.captureStart(');
      final statusRead = engine.indexOf('bindings.captureStatus()', captureStart);
      final activationHook = engine.indexOf('onCaptureStarted', statusRead);

      expect(captureStart, greaterThanOrEqualTo(0));
      expect(statusRead, greaterThan(captureStart));
      expect(activationHook, greaterThan(statusRead));
    });

    test('desktop runtime activates services before starting PCM pump', () {
      final runtime =
          File('lib/audio/native_desktop_runtime.dart').readAsStringSync();
      expect(runtime, contains('NativePcmServiceCoordinator'));
      expect(runtime, contains('NativePcmRuntimePump'));
      expect(runtime, contains('NativeRecordingDrain'));

      final activation = runtime.indexOf('await services.activateForCapture(status)');
      final pumpStart = runtime.indexOf('pump.start()', activation);
      expect(activation, greaterThanOrEqualTo(0));
      expect(pumpStart, greaterThan(activation));
    });

    test('no default capture sample rate is used to construct PCM services', () {
      final runtime =
          File('lib/audio/native_desktop_runtime.dart').readAsStringSync();
      final coordinator = File('lib/audio/native_pcm_service_coordinator.dart')
          .readAsStringSync();

      expect(runtime, isNot(contains('sampleRate: 48000')));
      expect(coordinator, contains('final rate = status.sampleRate.round()'));
      expect(coordinator, contains('sampleRate: rate'));
    });

    test('same Flutter process exposes acceptance telemetry to native mixer', () {
      final runtime =
          File('lib/audio/native_desktop_runtime.dart').readAsStringSync();
      final desktopSurface =
          File('lib/app/app_surface_desktop.dart').readAsStringSync();
      final wrapper =
          File('lib/features/mixer/mixer_desk_view.dart').readAsStringSync();
      final nativeMixer = File('lib/features/mixer/native_mixer_desk_view.dart')
          .readAsStringSync();

      expect(runtime, contains('NativeRuntimeAcceptanceTelemetry'));
      expect(runtime, contains('AcceptanceTelemetrySource? acceptanceTelemetry'));
      expect(runtime, contains('pcmRuntimePump: pump'));
      expect(
        desktopSurface,
        contains('telemetrySource: runtime.acceptanceTelemetry'),
      );
      expect(wrapper, contains('this.telemetrySource'));
      expect(wrapper, contains('telemetrySource: widget.telemetrySource'));
      expect(nativeMixer, contains('NativeAcceptanceTelemetryPanel'));
      expect(nativeMixer, contains('telemetrySource: telemetrySource'));
    });
  });
}
