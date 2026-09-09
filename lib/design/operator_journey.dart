/// Executable interaction contract for the repository-owned operator journey.
///
/// Canonical semantics live in `design/operator-journey.json`. This controller
/// intentionally has no UI, network, file-system, or audio dependencies.
enum OperatorStage {
  launch,
  routeSource,
  mix,
  preflight,
  recordOrStream,
  identify,
  correct,
  export,
  finalizeRecording,
  chooseLocationOrFinalizePartial,
}

enum RecoveryEvent {
  noDevice,
  permissionDenied,
  deviceLost,
  noSignal,
  clipping,
  diskFull,
  writeFailure,
  noMatch,
  offlineLookup,
  invalidCredentials,
  streamReconnecting,
  streamFailed,
}

class OperatorJourneyController {
  OperatorJourneyController({
    OperatorStage initialStage = OperatorStage.launch,
    this.recordingActive = false,
    this.broadcastActive = false,
  }) : stage = initialStage;

  OperatorStage stage;
  bool recordingActive;
  bool broadcastActive;
  RecoveryEvent? lastRecovery;

  static const List<OperatorStage> _successPath = <OperatorStage>[
    OperatorStage.launch,
    OperatorStage.routeSource,
    OperatorStage.mix,
    OperatorStage.preflight,
    OperatorStage.recordOrStream,
    OperatorStage.identify,
    OperatorStage.correct,
    OperatorStage.export,
    OperatorStage.finalizeRecording,
  ];

  void transitionTo(OperatorStage next) {
    if (stage == OperatorStage.chooseLocationOrFinalizePartial) {
      if (next == OperatorStage.recordOrStream ||
          next == OperatorStage.finalizeRecording) {
        stage = next;
        return;
      }
      throw StateError('Invalid recovery transition: $stage -> $next');
    }

    final index = _successPath.indexOf(stage);
    final nextIndex = _successPath.indexOf(next);
    if (index == -1 || nextIndex != index + 1) {
      throw StateError('Invalid operator transition: $stage -> $next');
    }
    stage = next;
  }

  void back() {
    stage = switch (stage) {
      OperatorStage.routeSource => OperatorStage.launch,
      OperatorStage.mix => OperatorStage.routeSource,
      OperatorStage.preflight => OperatorStage.mix,
      OperatorStage.recordOrStream => OperatorStage.preflight,
      OperatorStage.identify => OperatorStage.recordOrStream,
      OperatorStage.correct => OperatorStage.identify,
      OperatorStage.export => OperatorStage.correct,
      OperatorStage.finalizeRecording => OperatorStage.export,
      OperatorStage.chooseLocationOrFinalizePartial =>
        OperatorStage.recordOrStream,
      OperatorStage.launch => OperatorStage.launch,
    };
  }

  void recover(RecoveryEvent event) {
    lastRecovery = event;

    switch (event) {
      case RecoveryEvent.noDevice:
      case RecoveryEvent.permissionDenied:
        _requireStage(OperatorStage.routeSource, event);
        return;
      case RecoveryEvent.deviceLost:
      case RecoveryEvent.noSignal:
      case RecoveryEvent.clipping:
        _requireStage(OperatorStage.mix, event);
        return;
      case RecoveryEvent.invalidCredentials:
        _requireStage(OperatorStage.preflight, event);
        return;
      case RecoveryEvent.diskFull:
      case RecoveryEvent.writeFailure:
        _requireStage(OperatorStage.recordOrStream, event);
        stage = OperatorStage.chooseLocationOrFinalizePartial;
        return;
      case RecoveryEvent.streamReconnecting:
        _requireStage(OperatorStage.recordOrStream, event);
        return;
      case RecoveryEvent.streamFailed:
        _requireStage(OperatorStage.recordOrStream, event);
        broadcastActive = false;
        return;
      case RecoveryEvent.noMatch:
      case RecoveryEvent.offlineLookup:
        _requireStage(OperatorStage.identify, event);
        return;
    }
  }

  void _requireStage(OperatorStage expected, RecoveryEvent event) {
    if (stage != expected) {
      throw StateError('Recovery $event is invalid while stage is $stage');
    }
  }
}
