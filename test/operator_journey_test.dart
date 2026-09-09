import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/design/operator_journey.dart';

void main() {
  group('OperatorJourneyController', () {
    test('executes the canonical success path in order', () {
      final controller = OperatorJourneyController();

      expect(controller.stage, OperatorStage.launch);
      controller.transitionTo(OperatorStage.routeSource);
      controller.transitionTo(OperatorStage.mix);
      controller.transitionTo(OperatorStage.preflight);
      controller.transitionTo(OperatorStage.recordOrStream);
      controller.transitionTo(OperatorStage.identify);
      controller.transitionTo(OperatorStage.correct);
      controller.transitionTo(OperatorStage.export);
      controller.transitionTo(OperatorStage.finalizeRecording);

      expect(controller.stage, OperatorStage.finalizeRecording);
    });

    test('back follows the canonical previous operator step', () {
      final route = OperatorJourneyController(initialStage: OperatorStage.routeSource)..back();
      final correct = OperatorJourneyController(initialStage: OperatorStage.correct)..back();
      final export = OperatorJourneyController(initialStage: OperatorStage.export)..back();
      final finalize = OperatorJourneyController(initialStage: OperatorStage.finalizeRecording)..back();

      expect(route.stage, OperatorStage.launch);
      expect(correct.stage, OperatorStage.identify);
      expect(export.stage, OperatorStage.correct);
      expect(finalize.stage, OperatorStage.export);
    });

    test('routing and mixer recovery events remain retryable in place', () {
      final route = OperatorJourneyController(initialStage: OperatorStage.routeSource);
      route.recover(RecoveryEvent.noDevice);
      expect(route.stage, OperatorStage.routeSource);
      route.recover(RecoveryEvent.permissionDenied);
      expect(route.stage, OperatorStage.routeSource);

      final mixer = OperatorJourneyController(initialStage: OperatorStage.mix);
      for (final event in <RecoveryEvent>[
        RecoveryEvent.deviceLost,
        RecoveryEvent.noSignal,
        RecoveryEvent.clipping,
      ]) {
        mixer.recover(event);
        expect(mixer.stage, OperatorStage.mix);
      }
    });

    test('recording write failures enter location-or-partial-finalize recovery', () {
      for (final event in <RecoveryEvent>[RecoveryEvent.diskFull, RecoveryEvent.writeFailure]) {
        final controller = OperatorJourneyController(
          initialStage: OperatorStage.recordOrStream,
          recordingActive: true,
          broadcastActive: true,
        );

        controller.recover(event);

        expect(controller.stage, OperatorStage.chooseLocationOrFinalizePartial);
        expect(controller.recordingActive, isTrue);
      }
    });

    test('broadcast failure never implies local recording failure', () {
      final controller = OperatorJourneyController(
        initialStage: OperatorStage.recordOrStream,
        recordingActive: true,
        broadcastActive: true,
      );

      controller.recover(RecoveryEvent.streamFailed);

      expect(controller.stage, OperatorStage.recordOrStream);
      expect(controller.recordingActive, isTrue);
      expect(controller.broadcastActive, isFalse);
    });

    test('fingerprint no-match and offline lookup remain retryable', () {
      for (final event in <RecoveryEvent>[RecoveryEvent.noMatch, RecoveryEvent.offlineLookup]) {
        final controller = OperatorJourneyController(initialStage: OperatorStage.identify);
        controller.recover(event);
        expect(controller.stage, OperatorStage.identify);
        expect(controller.lastRecovery, event);
      }
    });

    test('invalid credentials return to preflight', () {
      final controller = OperatorJourneyController(initialStage: OperatorStage.preflight);
      controller.recover(RecoveryEvent.invalidCredentials);
      expect(controller.stage, OperatorStage.preflight);
    });

    test('rejects success-path transitions that are not adjacent', () {
      final controller = OperatorJourneyController();
      expect(
        () => controller.transitionTo(OperatorStage.recordOrStream),
        throwsA(isA<StateError>()),
      );
      expect(controller.stage, OperatorStage.launch);
    });
  });
}
