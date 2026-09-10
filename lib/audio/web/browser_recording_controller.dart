enum BrowserRecordingStatus {
  idle,
  starting,
  recording,
  stopping,
  readyToExport,
  exporting,
  error,
}

enum BrowserRecordingFailure {
  notReady,
  storageFull,
  writeFailed,
  exportFailed,
}

class BrowserRecordingException implements Exception {
  const BrowserRecordingException(this.failure, this.message);

  final BrowserRecordingFailure failure;
  final String message;

  @override
  String toString() => message;
}

class BrowserRecordingArtifact {
  const BrowserRecordingArtifact({
    required this.fileName,
    required this.bytesWritten,
    required this.dataBytes,
  });

  final String fileName;
  final int bytesWritten;
  final int dataBytes;
}

abstract interface class BrowserRecordingGateway {
  Future<void> startRecording();

  Future<BrowserRecordingArtifact> stopRecording();

  Future<void> exportRecording(BrowserRecordingArtifact artifact);
}

class BrowserRecordingState {
  const BrowserRecordingState({
    required this.status,
    required this.message,
    this.artifact,
  });

  const BrowserRecordingState.idle()
      : status = BrowserRecordingStatus.idle,
        message = 'RECORDING IDLE — START WHEN AUDIOWORKLET IS ACTIVE',
        artifact = null;

  final BrowserRecordingStatus status;
  final String message;
  final BrowserRecordingArtifact? artifact;
}

class BrowserRecordingController {
  BrowserRecordingController({required BrowserRecordingGateway gateway})
      : _gateway = gateway;

  final BrowserRecordingGateway _gateway;
  BrowserRecordingState _state = const BrowserRecordingState.idle();

  BrowserRecordingState get state => _state;

  Future<void> startRecording() async {
    _state = const BrowserRecordingState(
      status: BrowserRecordingStatus.starting,
      message: 'STARTING RECORDING — PREPARING WAV STORAGE',
    );

    try {
      await _gateway.startRecording();
      _state = const BrowserRecordingState(
        status: BrowserRecordingStatus.recording,
        message: 'RECORDING ACTIVE — POST-MASTER PCM TO WAV',
      );
    } on BrowserRecordingException catch (error) {
      _state = BrowserRecordingState(
        status: BrowserRecordingStatus.error,
        message: error.message,
      );
    } on Object catch (error) {
      _state = BrowserRecordingState(
        status: BrowserRecordingStatus.error,
        message: 'RECORDING FAILED — ${_sanitize(error)}',
      );
    }
  }

  Future<void> stopRecording() async {
    if (_state.status != BrowserRecordingStatus.recording) {
      _state = const BrowserRecordingState(
        status: BrowserRecordingStatus.error,
        message: 'RECORDING STOP FAILED — RECORDING NOT ACTIVE',
      );
      return;
    }

    _state = const BrowserRecordingState(
      status: BrowserRecordingStatus.stopping,
      message: 'FINALIZING WAV — FLUSHING RECORDING STORAGE',
    );

    try {
      final artifact = await _gateway.stopRecording();
      _state = BrowserRecordingState(
        status: BrowserRecordingStatus.readyToExport,
        message: 'WAV FINALIZED — ${artifact.fileName} — ${artifact.bytesWritten} BYTES',
        artifact: artifact,
      );
    } on BrowserRecordingException catch (error) {
      _state = BrowserRecordingState(
        status: BrowserRecordingStatus.error,
        message: error.message,
      );
    } on Object catch (error) {
      _state = BrowserRecordingState(
        status: BrowserRecordingStatus.error,
        message: 'RECORDING STOP FAILED — ${_sanitize(error)}',
      );
    }
  }

  Future<void> exportRecording() async {
    final artifact = _state.artifact;
    if (artifact == null) {
      _state = const BrowserRecordingState(
        status: BrowserRecordingStatus.error,
        message: 'WAV EXPORT UNAVAILABLE — NO FINALIZED RECORDING',
      );
      return;
    }

    _state = BrowserRecordingState(
      status: BrowserRecordingStatus.exporting,
      message: 'PREPARING WAV DOWNLOAD — ${artifact.fileName}',
      artifact: artifact,
    );

    try {
      await _gateway.exportRecording(artifact);
      _state = BrowserRecordingState(
        status: BrowserRecordingStatus.readyToExport,
        message: 'WAV DOWNLOAD REQUESTED — ${artifact.fileName}',
        artifact: artifact,
      );
    } on BrowserRecordingException catch (error) {
      _state = BrowserRecordingState(
        status: BrowserRecordingStatus.error,
        message: error.message,
        artifact: artifact,
      );
    } on Object catch (error) {
      _state = BrowserRecordingState(
        status: BrowserRecordingStatus.error,
        message: 'WAV EXPORT FAILED — ${_sanitize(error)}',
        artifact: artifact,
      );
    }
  }

  String _sanitize(Object error) {
    final compact = error
        .toString()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(
          RegExp(r'(?i)(token|password|authorization)=?[^ ,;]+'),
          r'$1=[REDACTED]',
        )
        .trim();
    return compact.isEmpty ? 'UNKNOWN ERROR' : compact;
  }
}
