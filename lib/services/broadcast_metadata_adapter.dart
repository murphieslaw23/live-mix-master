import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'broadcast_server_config.dart';
import 'fingerprint_service.dart';
import 'reliability_models.dart';
export 'broadcast_server_config.dart';

class BroadcastAdapterResult {
  const BroadcastAdapterResult({required this.protocol, required this.attemptCount, required this.safeEndpointIdentity, required this.succeeded, this.failureCode, this.diagnostic, this.operationId = 0, this.supersededBy});
  final BroadcastProtocol protocol;
  final int attemptCount;
  final String safeEndpointIdentity;
  final bool succeeded;
  final ServiceFailureCode? failureCode;
  final String? diagnostic;
  final int operationId;
  final int? supersededBy;
  ServiceOperationState get state => succeeded ? ServiceOperationState.succeeded : failureCode == ServiceFailureCode.cancelled ? ServiceOperationState.cancelled : ServiceOperationState.failed;
  String? get diagnosticCode => failureCode == null ? null : 'broadcast.${failureCode!.name}';
}

class BroadcastOperationStatus {
  const BroadcastOperationStatus(this.operationId, this.status);
  final int operationId;
  final ServiceStatus status;
}

String redactBroadcastDiagnostic(String value) => redactDiagnostic(value);

class BroadcastMetadataAdapter {
  BroadcastMetadataAdapter({required this.config, required Stream<IdentifiedTrack> fingerprintStream, http.Client? httpClient, http.Client Function()? clientFactory, Future<void> Function(Duration)? sleeper, Future<void> Function(String path, String content)? overlayWriter})
      : _client = _selectClient(httpClient, clientFactory),
        _shouldCloseClient = httpClient == null,
        _sleeper = sleeper,
        _overlayWriter = overlayWriter,
        _destinationId = ++_nextDestinationId,
        _fingerprintSub = fingerprintStream.listen(null) {
    _fingerprintSub.onData((track) { unawaited(sendMetadata(track)); });
  }
  static http.Client _selectClient(http.Client? client, http.Client Function()? factory) {
    if (client != null && factory != null) throw ArgumentError('Supply a client or a client factory, not both');
    return client ?? (factory == null ? http.Client() : factory());
  }
  static int _nextDestinationId = 0;
  final int _destinationId;
  final BroadcastServerConfig config;
  final StreamSubscription<IdentifiedTrack> _fingerprintSub;
  final http.Client _client;
  final bool _shouldCloseClient;
  final Future<void> Function(Duration)? _sleeper;
  final Future<void> Function(String path, String content)? _overlayWriter;
  final _statuses = StreamController<ServiceStatus>.broadcast();
  final _results = StreamController<BroadcastAdapterResult>.broadcast();
  final _operations = StreamController<BroadcastOperationStatus>.broadcast();
  _MetadataOperation? _active;
  _MetadataOperation? _pending;
  Future<void>? _worker;
  Future<void>? _disposeFuture;
  int _nextOperationId = 0;
  int _latestAcceptedId = 0;
  bool _closing = false;
  bool _eventsClosed = false;
  bool _isConnected = false;
  bool get isConnected => _isConnected;
  bool get isDisposed => _closing;
  int get pendingOperationCount => _pending == null ? 0 : 1;
  int? get activeOperationId => _active?.id;
  Stream<ServiceStatus> get onStatus => _statuses.stream;
  Stream<BroadcastAdapterResult> get onResult => _results.stream;
  Stream<BroadcastOperationStatus> get onOperationStatus => _operations.stream;
  String get safeEndpointIdentity => '${config.protocol.name}:destination-$_destinationId';

  static String _message(ServiceFailureCode code) {
    switch (code) {
      case ServiceFailureCode.invalidConfiguration: return 'Broadcast configuration is invalid.';
      case ServiceFailureCode.timeout: return 'Metadata request timed out.';
      case ServiceFailureCode.offline: return 'Metadata endpoint could not be reached.';
      case ServiceFailureCode.unauthorized: return 'Broadcast authentication failed.';
      case ServiceFailureCode.rateLimited: return 'Metadata endpoint rate limited the request.';
      case ServiceFailureCode.unavailable: return 'Metadata endpoint is unavailable.';
      case ServiceFailureCode.writeFailed: return 'Local overlay could not be updated.';
      case ServiceFailureCode.cancelled: return 'Metadata update cancelled.';
      default: return 'Metadata update failed.';
    }
  }

  Future<BroadcastAdapterResult> sendMetadata(IdentifiedTrack track) {
    final operation = _MetadataOperation(++_nextOperationId, track);
    if (_closing) return Future.value(_result(operation, ServiceFailureCode.cancelled, 'Broadcast adapter stopped.'));
    final invalid = config.validationFailure;
    if (invalid != null) { _finish(operation, invalid); return operation.completion.future; }
    _latestAcceptedId = operation.id;
    final pending = _pending;
    if (pending != null) _cancel(pending, supersededBy: operation.id);
    _pending = operation;
    final active = _active;
    if (active != null) _cancel(active, supersededBy: operation.id);
    _kick();
    return operation.completion.future;
  }

  void _kick() {
    if (_worker != null || _closing) return;
    _worker = Future<void>.microtask(_drain).whenComplete(() {
      _worker = null;
      if (!_closing && _pending != null) _kick();
    });
  }
  Future<void> _drain() async {
    while (!_closing && _pending != null) {
      final operation = _pending!;
      _pending = null;
      _active = operation;
      await _run(operation);
      _active = null;
    }
  }
  bool _current(_MetadataOperation operation) => !_closing && !operation.done && operation.id == _latestAcceptedId;

  Future<void> _run(_MetadataOperation operation) async {
    try {
      while (_current(operation) && operation.attempt < 1 + config.maxRetries) {
        operation.attempt++;
        _emit(operation, ServiceStatus.running(attempt: operation.attempt));
        final abort = Completer<void>();
        operation.requestAbort = abort;
        ServiceFailureCode? failure;
        try {
          failure = await _dispatch(operation, abort.future).timeout(config.timeout, onTimeout: () {
            if (!abort.isCompleted) abort.complete();
            throw TimeoutException('Metadata request timed out');
          });
        } catch (error) { failure = _mapException(error); }
        finally { operation.requestAbort = null; }
        if (!_current(operation)) return;
        if (failure == null) { _isConnected = true; _finish(operation, null); return; }
        if (!_retryable(failure) || operation.attempt > config.maxRetries) {
          _isConnected = false; _finish(operation, failure); return;
        }
        final backoff = config.retryDelay(operation.attempt);
        _emit(operation, ServiceStatus.retrying(failureCode: failure, attempt: operation.attempt, nextRetryAt: DateTime.now().add(backoff), message: _message(failure)));
        await _waitBackoff(operation, backoff);
      }
    } catch (error) {
      if (_current(operation)) { _isConnected = false; _finish(operation, _mapException(error)); }
    }
  }

  Future<void> _waitBackoff(_MetadataOperation operation, Duration duration) async {
    if (!_current(operation)) return;
    Future<void> delay;
    if (_sleeper != null) { delay = _sleeper(duration); }
    else {
      final completion = Completer<void>();
      operation.timer = Timer(duration, completion.complete);
      delay = completion.future;
    }
    try { await Future.any<void>([delay, operation.cancelled.future]); }
    finally { operation.timer?.cancel(); operation.timer = null; }
  }

  Future<ServiceFailureCode?> _dispatch(_MetadataOperation operation, Future<void> abortTrigger) async {
    final track = operation.track;
    if (config.protocol == BroadcastProtocol.obsHttpOverlay) {
      try {
        final path = config.overlayFilePath ?? 'live_current_track.txt';
        final content = '${track.artist.toUpperCase()} — ${track.title.toUpperCase()}';
        if (_overlayWriter != null) { await _overlayWriter(path, content); } else { await File(path).writeAsString(content, encoding: utf8, flush: true); }
        return null;
      } catch (_) { return ServiceFailureCode.writeFailed; }
    }
    final webhook = config.protocol == BroadcastProtocol.webhook;
    final request = http.AbortableRequest(webhook ? 'POST' : 'GET', config.buildMetadataUri('${track.artist} - ${track.title}'), abortTrigger: abortTrigger);
    if (config.protocol == BroadcastProtocol.icecast) request.headers['Authorization'] = 'Basic ${base64Encode(utf8.encode('${config.adminUser}:${config.adminPassword}'))}';
    if (webhook) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode({'event': 'track_change', 'artist': track.artist, 'title': track.title, 'release': track.release, 'confidence': track.confidence, 'detectedAt': track.detectedAt.toUtc().toIso8601String(), 'sessionOffsetMs': track.sessionOffset.inMilliseconds});
    }
    final response = await http.Response.fromStream(await _client.send(request));
    final status = response.statusCode;
    if (status >= 200 && status < 300) return null;
    if (status == 401 || status == 403) return ServiceFailureCode.unauthorized;
    if (status == 429) return ServiceFailureCode.rateLimited;
    if (status == 400 || status == 404) return ServiceFailureCode.invalidConfiguration;
    return status >= 500 ? ServiceFailureCode.unavailable : ServiceFailureCode.unknown;
  }

  static bool _retryable(ServiceFailureCode code) => code == ServiceFailureCode.timeout || code == ServiceFailureCode.offline || code == ServiceFailureCode.unavailable || code == ServiceFailureCode.rateLimited;
  static ServiceFailureCode _mapException(Object error) {
    if (error is http.RequestAbortedException) return ServiceFailureCode.cancelled;
    if (error is TimeoutException) return ServiceFailureCode.timeout;
    if (error is SocketException) return ServiceFailureCode.offline;
    if (error is FileSystemException) return ServiceFailureCode.writeFailed;
    return ServiceFailureCode.unavailable;
  }
  BroadcastAdapterResult _result(_MetadataOperation operation, ServiceFailureCode? failure, [String? message, int? supersededBy]) => BroadcastAdapterResult(protocol: config.protocol, attemptCount: operation.attempt, safeEndpointIdentity: safeEndpointIdentity, succeeded: failure == null, failureCode: failure, diagnostic: failure == null ? null : message ?? _message(failure), operationId: operation.id, supersededBy: supersededBy);

  void _emit(_MetadataOperation operation, ServiceStatus status) {
    if (_eventsClosed) return;
    _statuses.add(status);
    _operations.add(BroadcastOperationStatus(operation.id, status));
  }
  void _finish(_MetadataOperation operation, ServiceFailureCode? failure, {String? message, int? supersededBy}) {
    if (operation.done) return;
    final result = _result(operation, failure, message, supersededBy);
    final status = failure == null ? const ServiceStatus.succeeded() : failure == ServiceFailureCode.cancelled ? ServiceStatus.cancelled(message: result.diagnostic) : ServiceStatus.failed(failureCode: failure, message: result.diagnostic, attempt: operation.attempt);
    _emit(operation, status);
    if (!_eventsClosed) _results.add(result);
    operation.completion.complete(result);
  }
  void _cancel(_MetadataOperation operation, {int? supersededBy}) {
    if (operation.done) return;
    if (!operation.cancelled.isCompleted) operation.cancelled.complete();
    final abort = operation.requestAbort;
    if (abort != null && !abort.isCompleted) abort.complete();
    operation.timer?.cancel();
    _finish(operation, ServiceFailureCode.cancelled, message: supersededBy == null ? 'Broadcast adapter stopped.' : 'Superseded by a newer metadata update.', supersededBy: supersededBy);
  }

  Future<void> dispose() {
    if (_disposeFuture != null) return _disposeFuture!;
    _closing = true;
    _isConnected = false;
    final pending = _pending; _pending = null;
    if (pending != null) _cancel(pending);
    final active = _active; if (active != null) _cancel(active);
    return _disposeFuture = _close();
  }
  Future<void> _close() async {
    try {
      await _fingerprintSub.cancel();
      if (_shouldCloseClient) _client.close();
      final worker = _worker; if (worker != null) await worker;
    } finally {
      _eventsClosed = true;
      await Future.wait<void>([_statuses.close(), _results.close(), _operations.close()]);
    }
  }
}

class _MetadataOperation {
  _MetadataOperation(this.id, this.track);
  final int id;
  final IdentifiedTrack track;
  final completion = Completer<BroadcastAdapterResult>();
  final cancelled = Completer<void>();
  Completer<void>? requestAbort;
  Timer? timer;
  int attempt = 0;
  bool get done => completion.isCompleted;
}
