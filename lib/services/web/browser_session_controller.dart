import 'dart:async';

import '../fingerprint_tracklist_bridge.dart';
import '../live_session_tracklist_controller.dart';
import '../reliability_models.dart';
import '../session_tracklist.dart';
import '../session_tracklist_persister.dart';
import '../session_tracklist_repository.dart';
import '../tracklist_exporter.dart';

abstract interface class BrowserTracklistDownloadGateway {
  Future<void> download({
    required String fileName,
    required String mimeType,
    required String contents,
  });
}

typedef BrowserSessionStateListener = void Function(BrowserSessionState state);

class BrowserSessionState {
  const BrowserSessionState({
    required this.initialized,
    required this.entries,
    required this.persistenceStatus,
    this.sessionId,
  });

  const BrowserSessionState.idle()
      : initialized = false,
        sessionId = null,
        entries = const <TracklistEntry>[],
        persistenceStatus = const ServiceStatus.idle();

  final bool initialized;
  final String? sessionId;
  final List<TracklistEntry> entries;
  final ServiceStatus persistenceStatus;

  String? get persistenceWarning =>
      persistenceStatus.state == ServiceOperationState.failed
          ? (persistenceStatus.message ?? 'LOCAL SESSION PERSISTENCE FAILED')
          : null;
}

abstract interface class BrowserSessionPort {
  BrowserSessionState get state;

  void addListener(BrowserSessionStateListener listener);

  void removeListener(BrowserSessionStateListener listener);

  Future<void> initialize();

  Future<TracklistEntry> correct({
    required int index,
    required String artist,
    required String title,
  });

  Future<void> exportJson();

  Future<void> exportCsv();

  Future<void> exportM3u();

  Future<void> dispose();
}

class BrowserSessionController implements BrowserSessionPort {
  BrowserSessionController({
    required SessionTracklistRepository repository,
    required BrowserTracklistDownloadGateway downloadGateway,
    String Function()? createSessionId,
    DateTime Function()? clock,
    TracklistExporter exporter = const TracklistExporter(),
    this.defaultSourceId = 'browser-master',
  })  : _repository = repository,
        _downloadGateway = downloadGateway,
        _createSessionId = createSessionId,
        _clock = clock ?? DateTime.now,
        _exporter = exporter;

  final SessionTracklistRepository _repository;
  final BrowserTracklistDownloadGateway _downloadGateway;
  final String Function()? _createSessionId;
  final DateTime Function() _clock;
  final TracklistExporter _exporter;
  final String defaultSourceId;
  final Set<BrowserSessionStateListener> _listeners =
      <BrowserSessionStateListener>{};

  BrowserSessionState _state = const BrowserSessionState.idle();
  StreamSubscription<ServiceStatus>? _statusSubscription;
  SessionTracklistPersister? _persister;
  FingerprintTracklistBridge? _bridge;
  LiveSessionTracklistController? _live;
  bool _disposed = false;

  @override
  BrowserSessionState get state => _state;
  String? get sessionId => _state.sessionId;
  List<TracklistEntry> get entries => _state.entries;

  @override
  void addListener(BrowserSessionStateListener listener) {
    if (!_disposed) {
      _listeners.add(listener);
    }
  }

  @override
  void removeListener(BrowserSessionStateListener listener) {
    _listeners.remove(listener);
  }

  @override
  Future<void> initialize() async {
    _ensureNotDisposed();
    if (_state.initialized) {
      return;
    }

    _statusSubscription ??= _repository.onStatus.listen(_handlePersistenceStatus);

    List<TracklistEntry> recovered;
    try {
      recovered = await _repository.load();
    } on Object {
      recovered = const <TracklistEntry>[];
    }

    final resolvedSessionId = recovered.isNotEmpty
        ? recovered.first.sessionId
        : (_createSessionId?.call() ?? _defaultSessionId());
    final sourceId = recovered.isNotEmpty
        ? recovered.first.sourceId
        : defaultSourceId;
    final tracklist = SessionTracklist(initialEntries: recovered);
    final persister = SessionTracklistPersister(store: _repository);
    final bridge = FingerprintTracklistBridge(tracklist: tracklist);
    final live = LiveSessionTracklistController(
      sessionId: resolvedSessionId,
      sourceId: sourceId,
      tracklist: tracklist,
      bridge: bridge,
      persister: persister,
    );

    _persister = persister;
    _bridge = bridge;
    _live = live;
    _setState(
      BrowserSessionState(
        initialized: true,
        sessionId: resolvedSessionId,
        entries: List<TracklistEntry>.unmodifiable(live.entries),
        persistenceStatus: _state.persistenceStatus,
      ),
    );
  }

  @override
  Future<TracklistEntry> correct({
    required int index,
    required String artist,
    required String title,
  }) async {
    _ensureReady();
    final live = _live!;
    final corrected = live.correct(
      index: index,
      artist: artist,
      title: title,
      correctedAt: _clock().toUtc(),
    );
    _publishEntries();
    try {
      await _persister!.flush();
    } on Object {
      // The repository publishes a failed ServiceStatus. Corrections remain
      // available in memory so audio/session operation is not terminated.
    }
    return corrected;
  }

  @override
  Future<void> exportJson() => _export(
        format: ExportFormat.json,
        extension: 'json',
        mimeType: 'application/json',
      );

  @override
  Future<void> exportCsv() => _export(
        format: ExportFormat.csv,
        extension: 'csv',
        mimeType: 'text/csv;charset=utf-8',
      );

  @override
  Future<void> exportM3u() => _export(
        format: ExportFormat.m3u,
        extension: 'm3u',
        mimeType: 'audio/x-mpegurl',
      );

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _statusSubscription?.cancel();
    _statusSubscription = null;

    final live = _live;
    _live = null;
    _persister = null;
    if (live != null) {
      try {
        await live.close();
      } on Object {
        // Persistence failure is already represented as non-fatal state.
      }
    } else {
      await _repository.dispose();
    }

    await _bridge?.dispose();
    _bridge = null;
    _listeners.clear();
  }

  Future<void> _export({
    required ExportFormat format,
    required String extension,
    required String mimeType,
  }) async {
    _ensureReady();
    final currentSessionId = _state.sessionId!;
    final contents = _exporter.export(
      entries: _live!.entries,
      format: format,
      sessionName: currentSessionId,
      exportedAt: _clock().toUtc(),
    );
    await _downloadGateway.download(
      fileName: 'livemixmaster-${_safeFileName(currentSessionId)}.$extension',
      mimeType: mimeType,
      contents: contents,
    );
  }

  void _handlePersistenceStatus(ServiceStatus status) {
    if (_disposed) {
      return;
    }
    _setState(
      BrowserSessionState(
        initialized: _state.initialized,
        sessionId: _state.sessionId,
        entries: _state.entries,
        persistenceStatus: status,
      ),
    );
  }

  void _publishEntries() {
    final live = _live;
    if (live == null) {
      return;
    }
    _setState(
      BrowserSessionState(
        initialized: true,
        sessionId: _state.sessionId,
        entries: List<TracklistEntry>.unmodifiable(live.entries),
        persistenceStatus: _state.persistenceStatus,
      ),
    );
  }

  void _setState(BrowserSessionState next) {
    _state = next;
    for (final listener in List<BrowserSessionStateListener>.of(_listeners)) {
      listener(next);
    }
  }

  String _defaultSessionId() =>
      'web-${_clock().toUtc().microsecondsSinceEpoch}';

  String _safeFileName(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-');
    return normalized.isEmpty ? 'session' : normalized;
  }

  void _ensureReady() {
    _ensureNotDisposed();
    if (!_state.initialized || _live == null || _persister == null) {
      throw StateError('BROWSER SESSION NOT INITIALIZED');
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('BrowserSessionController is disposed');
    }
  }
}
