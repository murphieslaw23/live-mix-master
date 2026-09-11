import 'fingerprint_proxy_client.dart';

enum BrowserFingerprintLookupStatus {
  idle,
  lookingUp,
  matched,
  noMatch,
  failed,
}

class BrowserFingerprintLookupState {
  final BrowserFingerprintLookupStatus status;
  final String message;
  final FingerprintProxyTrack? track;
  final FingerprintProxyFailureCode? failureCode;

  const BrowserFingerprintLookupState({
    required this.status,
    required this.message,
    this.track,
    this.failureCode,
  });

  const BrowserFingerprintLookupState.idle()
      : this(
          status: BrowserFingerprintLookupStatus.idle,
          message: 'FINGERPRINT PROXY READY — AWAITING PREPARED FINGERPRINT',
        );
}

abstract interface class BrowserFingerprintLookupGateway {
  Future<FingerprintProxyResult> lookup({
    required String fingerprint,
    required int durationSeconds,
    double minimumConfidence = 0.65,
  });
}

class FingerprintProxyLookupGateway implements BrowserFingerprintLookupGateway {
  FingerprintProxyLookupGateway({FingerprintProxyClient? client})
      : _client = client ?? FingerprintProxyClient(),
        _ownsClient = client == null;

  final FingerprintProxyClient _client;
  final bool _ownsClient;

  @override
  Future<FingerprintProxyResult> lookup({
    required String fingerprint,
    required int durationSeconds,
    double minimumConfidence = 0.65,
  }) {
    return _client.lookup(
      fingerprint: fingerprint,
      durationSeconds: durationSeconds,
      minimumConfidence: minimumConfidence,
    );
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}

typedef BrowserFingerprintLookupListener = void Function(
  BrowserFingerprintLookupState state,
);

class _BrowserFingerprintLookupStore {
  BrowserFingerprintLookupState state = const BrowserFingerprintLookupState.idle();
  final Set<BrowserFingerprintLookupListener> listeners = {};
}

final _BrowserFingerprintLookupStore _defaultFingerprintLookupStore =
    _BrowserFingerprintLookupStore();

class BrowserFingerprintLookupController {
  BrowserFingerprintLookupController({BrowserFingerprintLookupGateway? gateway})
      : _gateway = gateway ?? FingerprintProxyLookupGateway(),
        _store = gateway == null
            ? _defaultFingerprintLookupStore
            : _BrowserFingerprintLookupStore();

  final BrowserFingerprintLookupGateway _gateway;
  final _BrowserFingerprintLookupStore _store;
  final Set<BrowserFingerprintLookupListener> _ownedListeners = {};

  BrowserFingerprintLookupState get state => _store.state;

  void addListener(BrowserFingerprintLookupListener listener) {
    _ownedListeners.add(listener);
    _store.listeners.add(listener);
  }

  void removeListener(BrowserFingerprintLookupListener listener) {
    _ownedListeners.remove(listener);
    _store.listeners.remove(listener);
  }

  Future<void> lookupPreparedFingerprint({
    required String fingerprint,
    required int durationSeconds,
    double minimumConfidence = 0.65,
  }) async {
    _setState(
      const BrowserFingerprintLookupState(
        status: BrowserFingerprintLookupStatus.lookingUp,
        message: 'FINGERPRINT LOOKUP IN PROGRESS — MIX / RECORDING CONTINUE',
      ),
    );

    final result = await _gateway.lookup(
      fingerprint: fingerprint,
      durationSeconds: durationSeconds,
      minimumConfidence: minimumConfidence,
    );

    switch (result.outcome) {
      case FingerprintProxyOutcome.matched:
        final track = result.track;
        if (track == null) {
          _setState(_failed(FingerprintProxyFailureCode.malformedResponse));
          return;
        }
        final confidencePercent = (track.confidence * 100).round();
        _setState(
          BrowserFingerprintLookupState(
            status: BrowserFingerprintLookupStatus.matched,
            message:
                'TRACK MATCH — ${track.artist.toUpperCase()} — ${track.title.toUpperCase()} — $confidencePercent%',
            track: track,
          ),
        );
      case FingerprintProxyOutcome.noMatch:
        _setState(
          const BrowserFingerprintLookupState(
            status: BrowserFingerprintLookupStatus.noMatch,
            message: 'NO CONFIDENT TRACK MATCH — SESSION CONTINUES',
          ),
        );
      case FingerprintProxyOutcome.failed:
        _setState(_failed(result.failureCode ?? FingerprintProxyFailureCode.unknown));
    }
  }

  void reportPreparationUnavailable() {
    _setState(
      const BrowserFingerprintLookupState(
        status: BrowserFingerprintLookupStatus.failed,
        failureCode: FingerprintProxyFailureCode.unavailable,
        message: 'FINGERPRINT PREPARATION UNAVAILABLE — MIX / RECORDING CONTINUE',
      ),
    );
  }

  void dispose() {
    for (final listener in List<BrowserFingerprintLookupListener>.of(_ownedListeners)) {
      _store.listeners.remove(listener);
    }
    _ownedListeners.clear();
    if (_gateway is FingerprintProxyLookupGateway) {
      (_gateway as FingerprintProxyLookupGateway).close();
    }
  }

  BrowserFingerprintLookupState _failed(FingerprintProxyFailureCode code) {
    return BrowserFingerprintLookupState(
      status: BrowserFingerprintLookupStatus.failed,
      failureCode: code,
      message: _failureMessage(code),
    );
  }

  void _setState(BrowserFingerprintLookupState state) {
    _store.state = state;
    for (final listener in List<BrowserFingerprintLookupListener>.of(_store.listeners)) {
      listener(state);
    }
  }

  static String _failureMessage(FingerprintProxyFailureCode code) {
    switch (code) {
      case FingerprintProxyFailureCode.rateLimited:
        return 'FINGERPRINT PROVIDER RATE LIMITED — RETRY LATER';
      case FingerprintProxyFailureCode.timeout:
        return 'FINGERPRINT PROVIDER TIMEOUT — MIX / RECORDING CONTINUE';
      case FingerprintProxyFailureCode.offline:
        return 'FINGERPRINT PROXY OFFLINE — MIX / RECORDING CONTINUE';
      case FingerprintProxyFailureCode.invalidConfiguration:
        return 'FINGERPRINT PROVIDER NOT CONFIGURED — MIX / RECORDING CONTINUE';
      case FingerprintProxyFailureCode.unauthorized:
        return 'FINGERPRINT PROVIDER AUTH FAILED — SERVER CONFIGURATION REQUIRED';
      case FingerprintProxyFailureCode.cancelled:
        return 'FINGERPRINT LOOKUP CANCELLED — SESSION CONTINUES';
      case FingerprintProxyFailureCode.invalidRequest:
      case FingerprintProxyFailureCode.malformedResponse:
      case FingerprintProxyFailureCode.unavailable:
      case FingerprintProxyFailureCode.unknown:
        return 'FINGERPRINT PROVIDER UNAVAILABLE — MIX / RECORDING CONTINUE';
    }
  }
}
