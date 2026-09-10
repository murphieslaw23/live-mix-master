enum BrowserCaptureKind {
  microphone,
  displayAudio,
}

enum BrowserCaptureStatus {
  idle,
  permissionRequired,
  requesting,
  active,
  permissionDenied,
  noAudioTrack,
  unsupported,
  reconnectRequired,
  deviceInventoryChanged,
  error,
}

class BrowserAudioCapabilities {
  const BrowserAudioCapabilities({
    required this.mediaDevicesAvailable,
    required this.microphoneCaptureAvailable,
    required this.displayCaptureAvailable,
    required this.systemAudioGuaranteed,
  });

  final bool mediaDevicesAvailable;
  final bool microphoneCaptureAvailable;
  final bool displayCaptureAvailable;
  final bool systemAudioGuaranteed;

  bool get hasCapturePath =>
      mediaDevicesAvailable &&
      (microphoneCaptureAvailable || displayCaptureAvailable);
}

class BrowserCaptureSource {
  const BrowserCaptureSource({
    required this.kind,
    required this.id,
    required this.label,
  });

  final BrowserCaptureKind kind;
  final String id;
  final String label;
}

enum BrowserCaptureAttemptStatus {
  connected,
  permissionDenied,
  noAudioTrack,
  unsupported,
  failed,
}

class BrowserCaptureAttempt {
  const BrowserCaptureAttempt._({
    required this.status,
    this.source,
    this.message,
  });

  const BrowserCaptureAttempt.connected(BrowserCaptureSource source)
      : this._(
          status: BrowserCaptureAttemptStatus.connected,
          source: source,
        );

  const BrowserCaptureAttempt.permissionDenied()
      : this._(status: BrowserCaptureAttemptStatus.permissionDenied);

  const BrowserCaptureAttempt.noAudioTrack()
      : this._(status: BrowserCaptureAttemptStatus.noAudioTrack);

  const BrowserCaptureAttempt.unsupported()
      : this._(status: BrowserCaptureAttemptStatus.unsupported);

  const BrowserCaptureAttempt.failed([String? message])
      : this._(
          status: BrowserCaptureAttemptStatus.failed,
          message: message,
        );

  final BrowserCaptureAttemptStatus status;
  final BrowserCaptureSource? source;
  final String? message;
}

abstract interface class BrowserMediaGateway {
  Future<BrowserAudioCapabilities> probeCapabilities();

  Future<BrowserCaptureAttempt> requestMicrophone();

  Future<BrowserCaptureAttempt> requestDisplayAudio();
}

abstract interface class BrowserMediaLifecycleGateway {
  void setTrackEndedHandler(void Function() handler);

  void setDeviceChangeHandler(void Function() handler);
}

typedef BrowserCaptureStateListener = void Function(BrowserCaptureState state);

class BrowserCaptureState {
  const BrowserCaptureState({
    required this.status,
    required this.message,
    this.capabilities,
    this.source,
  });

  const BrowserCaptureState.idle()
      : status = BrowserCaptureStatus.idle,
        message = 'BROWSER AUDIO IDLE',
        capabilities = null,
        source = null;

  final BrowserCaptureStatus status;
  final String message;
  final BrowserAudioCapabilities? capabilities;
  final BrowserCaptureSource? source;

  BrowserCaptureState copyWith({
    BrowserCaptureStatus? status,
    String? message,
    BrowserAudioCapabilities? capabilities,
    BrowserCaptureSource? source,
    bool clearSource = false,
  }) {
    return BrowserCaptureState(
      status: status ?? this.status,
      message: message ?? this.message,
      capabilities: capabilities ?? this.capabilities,
      source: clearSource ? null : (source ?? this.source),
    );
  }
}

class BrowserCaptureController {
  BrowserCaptureController({required BrowserMediaGateway gateway})
      : _gateway = gateway {
    if (gateway is BrowserMediaLifecycleGateway) {
      final lifecycleGateway = gateway as BrowserMediaLifecycleGateway;
      lifecycleGateway.setTrackEndedHandler(handleTrackEnded);
      lifecycleGateway.setDeviceChangeHandler(handleDeviceChange);
    }
  }

  final BrowserMediaGateway _gateway;
  final List<BrowserCaptureStateListener> _listeners =
      <BrowserCaptureStateListener>[];

  BrowserCaptureState _state = const BrowserCaptureState.idle();

  BrowserCaptureState get state => _state;

  void addListener(BrowserCaptureStateListener listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  void removeListener(BrowserCaptureStateListener listener) {
    _listeners.remove(listener);
  }

  Future<void> probe() async {
    try {
      final capabilities = await _gateway.probeCapabilities();
      if (!capabilities.hasCapturePath) {
        _setState(
          BrowserCaptureState(
            status: BrowserCaptureStatus.unsupported,
            capabilities: capabilities,
            message: 'BROWSER AUDIO CAPTURE NOT EXPOSED BY THIS BROWSER / OS',
          ),
        );
        return;
      }

      _setState(
        BrowserCaptureState(
          status: BrowserCaptureStatus.permissionRequired,
          capabilities: capabilities,
          message: 'SOURCE PERMISSION REQUIRED',
        ),
      );
    } on Object catch (error) {
      _setState(
        BrowserCaptureState(
          status: BrowserCaptureStatus.error,
          message: _sanitizedFailure('CAPABILITY PROBE FAILED', error),
        ),
      );
    }
  }

  Future<void> requestMicrophone() async {
    await _request(
      request: _gateway.requestMicrophone,
      fallbackKind: BrowserCaptureKind.microphone,
    );
  }

  Future<void> requestDisplayAudio() async {
    await _request(
      request: _gateway.requestDisplayAudio,
      fallbackKind: BrowserCaptureKind.displayAudio,
    );
  }

  void handleTrackEnded() {
    _setState(
      _state.copyWith(
        status: BrowserCaptureStatus.reconnectRequired,
        message: 'CAPTURE ENDED / ACCESS REVOKED — RECONNECT REQUIRED',
        clearSource: true,
      ),
    );
  }

  void handleDeviceChange() {
    _setState(
      _state.copyWith(
        status: BrowserCaptureStatus.deviceInventoryChanged,
        message: 'AUDIO DEVICE LIST CHANGED — VERIFY SOURCE / RECONNECT IF NEEDED',
      ),
    );
  }

  Future<void> _request({
    required Future<BrowserCaptureAttempt> Function() request,
    required BrowserCaptureKind fallbackKind,
  }) async {
    _setState(
      _state.copyWith(
        status: BrowserCaptureStatus.requesting,
        message: fallbackKind == BrowserCaptureKind.microphone
            ? 'REQUESTING MIC / USB AUDIO'
            : 'REQUESTING TAB / WINDOW AUDIO',
        clearSource: true,
      ),
    );

    try {
      final attempt = await request();
      _applyAttempt(attempt);
    } on Object catch (error) {
      _setState(
        _state.copyWith(
          status: BrowserCaptureStatus.error,
          message: _sanitizedFailure('BROWSER CAPTURE FAILED', error),
          clearSource: true,
        ),
      );
    }
  }

  void _applyAttempt(BrowserCaptureAttempt attempt) {
    switch (attempt.status) {
      case BrowserCaptureAttemptStatus.connected:
        final source = attempt.source;
        if (source == null) {
          _setState(
            _state.copyWith(
              status: BrowserCaptureStatus.error,
              message: 'BROWSER CAPTURE FAILED — SOURCE METADATA MISSING',
              clearSource: true,
            ),
          );
          return;
        }
        _setState(
          _state.copyWith(
            status: BrowserCaptureStatus.active,
            source: source,
            message: 'CAPTURE ACTIVE — ${source.label}',
          ),
        );
      case BrowserCaptureAttemptStatus.permissionDenied:
        _setState(
          _state.copyWith(
            status: BrowserCaptureStatus.permissionDenied,
            message: 'AUDIO PERMISSION DENIED — ALLOW ACCESS AND RETRY',
            clearSource: true,
          ),
        );
      case BrowserCaptureAttemptStatus.noAudioTrack:
        _setState(
          _state.copyWith(
            status: BrowserCaptureStatus.noAudioTrack,
            message: 'NO AUDIO TRACK RETURNED — SELECT A SOURCE THAT SHARES AUDIO',
            clearSource: true,
          ),
        );
      case BrowserCaptureAttemptStatus.unsupported:
        _setState(
          _state.copyWith(
            status: BrowserCaptureStatus.unsupported,
            message: 'REQUESTED AUDIO SOURCE NOT EXPOSED BY THIS BROWSER / OS',
            clearSource: true,
          ),
        );
      case BrowserCaptureAttemptStatus.failed:
        _setState(
          _state.copyWith(
            status: BrowserCaptureStatus.error,
            message: attempt.message == null || attempt.message!.trim().isEmpty
                ? 'BROWSER CAPTURE FAILED'
                : 'BROWSER CAPTURE FAILED — ${attempt.message!.trim()}',
            clearSource: true,
          ),
        );
    }
  }

  void _setState(BrowserCaptureState nextState) {
    _state = nextState;
    for (final listener in List<BrowserCaptureStateListener>.of(_listeners)) {
      listener(_state);
    }
  }

  String _sanitizedFailure(String prefix, Object error) {
    final compact = error
        .toString()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(
          RegExp(r'(?i)(token|password|authorization)=?[^ ,;]+'),
          r'$1=[REDACTED]',
        )
        .trim();
    return compact.isEmpty ? prefix : '$prefix — $compact';
  }
}
