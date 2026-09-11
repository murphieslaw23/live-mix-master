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
  backpressure,
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

abstract interface class BrowserRecordingLifecycleGateway {
  void setRecordingFailureHandler(
    void Function(BrowserRecordingException failure) handler,
  );
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

typedef BrowserRecordingStateListener = void Function(BrowserRecordingState state);

class BrowserRecordingController {
  BrowserRecordingController({required BrowserRecordingGateway gateway})
      : _gateway = gateway {
    final lifecycleGateway = gateway is BrowserRecordingLifecycleGateway
        ? gateway as BrowserRecordingLifecycleGateway
        : null;
    lifecycleGateway?.setRecordingFailureHandler(_handleGatewayFailure);
  }

  final BrowserRecordingGateway _gateway;
  final Set<BrowserRecordingStateListener> _listeners =
      <BrowserRecordingStateListener>{};
  BrowserRecordingState _state = const BrowserRecordingState.idle();

  BrowserRecordingState get state => _state;

  void addListener(BrowserRecordingStateListener listener) {
    _listeners.add(listener);
  }

  void removeListener(BrowserRecordingStateListener listener) {
    _listeners.remove(listener);
  }

  Future<void> startRecording() async {
    _setState(
      const BrowserRecordingState(
        status: BrowserRecordingStatus.starting,
        message: 'STARTING RECORDING — PREPARING WAV STORAGE',
      ),
    );

    try {
      await _gateway.startRecording();
      _setState(
        const BrowserRecordingState(
          status: BrowserRecordingStatus.recording,
          message: 'RECORDING ACTIVE — POST-MASTER PCM TO WAV',
        ),
      );
    } on BrowserRecordingException catch (error) {
      _setState(
        BrowserRecordingState(
          status: BrowserRecordingStatus.error,
          message: error.message,
        ),
      );
    } on Object catch (error) {
      _setState(
        BrowserRecordingState(
          status: BrowserRecordingStatus.error,
          message: 'RECORDING FAILED — ${_sanitize(error)}',
        ),
      );
    }
  }

  Future<void> stopRecording() async {
    if (_state.status != BrowserRecordingStatus.recording) {
      _setState(
        const BrowserRecordingState(
          status: BrowserRecordingStatus.error,
          message: 'RECORDING STOP FAILED — RECORDING NOT ACTIVE',
        ),
      );
      return;
    }

    _setState(
      const BrowserRecordingState(
        status: BrowserRecordingStatus.stopping,
        message: 'FINALIZING WAV — FLUSHING RECORDING STORAGE',
      ),
    );

    try {
      final artifact = await _gateway.stopRecording();
      _setState(
        BrowserRecordingState(
          status: BrowserRecordingStatus.readyToExport,
          message: 'WAV FINALIZED — ${artifact.fileName} — ${artifact.bytesWritten} BYTES',
          artifact: artifact,
        ),
      );
    } on BrowserRecordingException catch (error) {
      _setState(
        BrowserRecordingState(
          status: BrowserRecordingStatus.error,
          message: error.message,
        ),
      );
    } on Object catch (error) {
      _setState(
        BrowserRecordingState(
          status: BrowserRecordingStatus.error,
          message: 'RECORDING STOP FAILED — ${_sanitize(error)}',
        ),
      );
    }
  }

  Future<void> exportRecording() async {
    final artifact = _state.artifact;
    if (artifact == null) {
      _setState(
        const BrowserRecordingState(
          status: BrowserRecordingStatus.error,
          message: 'WAV EXPORT UNAVAILABLE — NO FINALIZED RECORDING',
        ),
      );
      return;
    }

    _setState(
      BrowserRecordingState(
        status: BrowserRecordingStatus.exporting,
        message: 'PREPARING WAV DOWNLOAD — ${artifact.fileName}',
        artifact: artifact,
      ),
    );

    try {
      await _gateway.exportRecording(artifact);
      _setState(
        BrowserRecordingState(
          status: BrowserRecordingStatus.readyToExport,
          message: 'WAV DOWNLOAD REQUESTED — ${artifact.fileName}',
          artifact: artifact,
        ),
      );
    } on BrowserRecordingException catch (error) {
      _setState(
        BrowserRecordingState(
          status: BrowserRecordingStatus.error,
          message: error.message,
          artifact: artifact,
        ),
      );
    } on Object catch (error) {
      _setState(
        BrowserRecordingState(
          status: BrowserRecordingStatus.error,
          message: 'WAV EXPORT FAILED — ${_sanitize(error)}',
          artifact: artifact,
        ),
      );
    }
  }

  void _handleGatewayFailure(BrowserRecordingException failure) {
    switch (_state.status) {
      case BrowserRecordingStatus.starting:
      case BrowserRecordingStatus.recording:
      case BrowserRecordingStatus.stopping:
      case BrowserRecordingStatus.exporting:
        _setState(
          BrowserRecordingState(
            status: BrowserRecordingStatus.error,
            message: failure.message,
            artifact: _state.artifact,
          ),
        );
      case BrowserRecordingStatus.idle:
      case BrowserRecordingStatus.readyToExport:
      case BrowserRecordingStatus.error:
        break;
    }
  }

  void _setState(BrowserRecordingState state) {
    _state = state;
    for (final listener in List<BrowserRecordingStateListener>.of(_listeners)) {
      listener(state);
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
