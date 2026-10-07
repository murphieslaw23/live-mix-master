import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'fingerprint_service.dart';
import 'reliability_models.dart';

enum BroadcastProtocol { icecast, shoutcast, webhook, obsHttpOverlay }

class BroadcastServerConfig {
  const BroadcastServerConfig({required this.protocol, this.host = 'localhost', this.port = 8000, this.mountPoint = '/live', this.adminUser = 'admin', this.adminPassword = '', this.webhookUrl, this.timeout = const Duration(seconds: 4), this.maxRetries = 2, this.initialBackoff = const Duration(milliseconds: 100), this.overlayFilePath});
  final BroadcastProtocol protocol;
  final String host;
  final int port;
  final String mountPoint;
  final String adminUser;
  final String adminPassword;
  final Uri? webhookUrl;
  final Duration timeout;
  final int maxRetries;
  final Duration initialBackoff;
  final String? overlayFilePath;
  ServiceFailureCode? get validationFailure {
    switch (protocol) {
      case BroadcastProtocol.icecast:
      case BroadcastProtocol.shoutcast:
        if (host.trim().isEmpty || port <= 0 || port > 65535) return ServiceFailureCode.invalidConfiguration;
        break;
      case BroadcastProtocol.webhook:
        if (webhookUrl == null || !webhookUrl!.hasScheme || webhookUrl!.host.isEmpty) return ServiceFailureCode.invalidConfiguration;
        break;
      case BroadcastProtocol.obsHttpOverlay:
        break;
    }
    return null;
  }
}

class BroadcastAdapterResult {
  const BroadcastAdapterResult({required this.protocol, required this.attemptCount, required this.safeEndpointIdentity, required this.succeeded, this.failureCode, this.diagnostic});
  final BroadcastProtocol protocol;
  final int attemptCount;
  final String safeEndpointIdentity;
  final bool succeeded;
  final ServiceFailureCode? failureCode;
  final String? diagnostic;
  String? get diagnosticCode => failureCode == null ? null : 'broadcast.${failureCode!.name}';
}

String redactBroadcastDiagnostic(String value) => redactDiagnostic(value);

class BroadcastMetadataAdapter {
  BroadcastMetadataAdapter({required this.config, required Stream<IdentifiedTrack> fingerprintStream, http.Client? httpClient, Future<void> Function(Duration)? sleeper})
      : _client = httpClient ?? http.Client(),
        _shouldCloseClient = httpClient == null,
        _sleeper = sleeper,
        _destinationId = ++_nextDestinationId,
        _fingerprintSub = fingerprintStream.listen(null) {
    _fingerprintSub.onData(_onTrackDetected);
  }
  static int _nextDestinationId = 0;
  final int _destinationId;
  final BroadcastServerConfig config;
  final StreamSubscription<IdentifiedTrack> _fingerprintSub;
  final http.Client _client;
  final bool _shouldCloseClient;
  final Future<void> Function(Duration)? _sleeper;
  final _statusController = StreamController<ServiceStatus>.broadcast(sync: true);
  final _resultController = StreamController<BroadcastAdapterResult>.broadcast(sync: true);
  bool _isConnected = false;
  bool get isConnected => _isConnected;
  Stream<ServiceStatus> get onStatus => _statusController.stream;
  Stream<BroadcastAdapterResult> get onResult => _resultController.stream;
  String get safeEndpointIdentity => '${config.protocol.name}:destination-$_destinationId';

  void _onTrackDetected(IdentifiedTrack track) { sendMetadata(track); }

  static String _message(ServiceFailureCode code) {
    switch (code) {
      case ServiceFailureCode.invalidConfiguration: return 'Broadcast configuration is invalid.';
      case ServiceFailureCode.timeout: return 'Metadata request timed out.';
      case ServiceFailureCode.offline: return 'Metadata endpoint could not be reached.';
      case ServiceFailureCode.unauthorized: return 'Broadcast authentication failed.';
      case ServiceFailureCode.rateLimited: return 'Metadata endpoint rate limited the request.';
      case ServiceFailureCode.unavailable: return 'Metadata endpoint is unavailable.';
      case ServiceFailureCode.writeFailed: return 'Local overlay could not be updated.';
      default: return 'Metadata update failed.';
    }
  }

  Future<BroadcastAdapterResult> sendMetadata(IdentifiedTrack track) async {
    final validation = config.validationFailure;
    if (validation != null) {
      final diagnostic = _message(validation);
      _emitStatus(ServiceStatus.failed(failureCode: validation, message: diagnostic));
      final result = BroadcastAdapterResult(protocol: config.protocol, attemptCount: 0, safeEndpointIdentity: safeEndpointIdentity, succeeded: false, failureCode: validation, diagnostic: diagnostic);
      _emitResult(result);
      return result;
    }
    final maxAttempts = 1 + config.maxRetries;
    var attempt = 0;
    ServiceFailureCode? lastFailureCode;
    while (attempt < maxAttempts) {
      attempt++;
      _emitStatus(ServiceStatus.running(attempt: attempt));
      try {
        final outcome = await _executeDispatch(track);
        if (outcome.succeeded) {
          _isConnected = true;
          _emitStatus(const ServiceStatus.succeeded());
          final result = BroadcastAdapterResult(protocol: config.protocol, attemptCount: attempt, safeEndpointIdentity: safeEndpointIdentity, succeeded: true);
          _emitResult(result);
          return result;
        }
        lastFailureCode = outcome.failureCode ?? ServiceFailureCode.unknown;
        if (!_isRetryableCode(lastFailureCode) || attempt >= maxAttempts) break;
        final backoff = config.initialBackoff * (1 << (attempt - 1));
        _emitStatus(ServiceStatus.retrying(failureCode: lastFailureCode, attempt: attempt, nextRetryAt: DateTime.now().add(backoff), message: _message(lastFailureCode)));
        if (_sleeper != null) { await _sleeper(backoff); } else { await Future<void>.delayed(backoff); }
      } catch (error) {
        lastFailureCode = _mapExceptionToFailureCode(error);
        if (!_isRetryableCode(lastFailureCode) || attempt >= maxAttempts) break;
        final backoff = config.initialBackoff * (1 << (attempt - 1));
        _emitStatus(ServiceStatus.retrying(failureCode: lastFailureCode, attempt: attempt, nextRetryAt: DateTime.now().add(backoff), message: _message(lastFailureCode)));
        if (_sleeper != null) { await _sleeper(backoff); } else { await Future<void>.delayed(backoff); }
      }
    }
    _isConnected = false;
    final code = lastFailureCode ?? ServiceFailureCode.unknown;
    final diagnostic = _message(code);
    _emitStatus(ServiceStatus.failed(failureCode: code, message: diagnostic, attempt: attempt));
    final result = BroadcastAdapterResult(protocol: config.protocol, attemptCount: attempt, safeEndpointIdentity: safeEndpointIdentity, succeeded: false, failureCode: code, diagnostic: diagnostic);
    _emitResult(result);
    return result;
  }

  Future<_DispatchOutcome> _executeDispatch(IdentifiedTrack track) async {
    final song = '${track.artist} - ${track.title}';
    switch (config.protocol) {
      case BroadcastProtocol.icecast: return _dispatchIcecast(song);
      case BroadcastProtocol.shoutcast: return _dispatchShoutcast(song);
      case BroadcastProtocol.webhook: return _dispatchWebhook(track);
      case BroadcastProtocol.obsHttpOverlay: return _dispatchOverlay(track);
    }
  }

  Future<_DispatchOutcome> _dispatchIcecast(String song) async {
    final mount = config.mountPoint.startsWith('/') ? config.mountPoint : '/${config.mountPoint}';
    final uri = Uri(scheme: 'http', host: config.host, port: config.port, path: '/admin/metadata', queryParameters: {'mount': mount, 'mode': 'updinfo', 'song': song, 'charset': 'UTF-8'});
    final basicAuth = 'Basic ${base64Encode(utf8.encode('${config.adminUser}:${config.adminPassword}'))}';
    try {
      return _interpretHttpResponse(await _client.get(uri, headers: {'Authorization': basicAuth}).timeout(config.timeout));
    } catch (error) { return _DispatchOutcome(succeeded: false, failureCode: _mapExceptionToFailureCode(error)); }
  }

  Future<_DispatchOutcome> _dispatchShoutcast(String song) async {
    final uri = Uri(scheme: 'http', host: config.host, port: config.port, path: '/admin.cgi', queryParameters: {'mode': 'updinfo', 'pass': config.adminPassword, 'song': song});
    try {
      return _interpretHttpResponse(await _client.get(uri).timeout(config.timeout));
    } catch (error) { return _DispatchOutcome(succeeded: false, failureCode: _mapExceptionToFailureCode(error)); }
  }

  Future<_DispatchOutcome> _dispatchWebhook(IdentifiedTrack track) async {
    final url = config.webhookUrl;
    if (url == null) return const _DispatchOutcome(succeeded: false, failureCode: ServiceFailureCode.invalidConfiguration);
    final payload = jsonEncode({'event': 'track_change', 'artist': track.artist, 'title': track.title, 'release': track.release, 'confidence': track.confidence, 'detectedAt': track.detectedAt.toUtc().toIso8601String(), 'sessionOffsetMs': track.sessionOffset.inMilliseconds});
    try {
      return _interpretHttpResponse(await _client.post(url, headers: {'Content-Type': 'application/json; charset=utf-8'}, body: payload).timeout(config.timeout));
    } catch (error) { return _DispatchOutcome(succeeded: false, failureCode: _mapExceptionToFailureCode(error)); }
  }

  Future<_DispatchOutcome> _dispatchOverlay(IdentifiedTrack track) async {
    try {
      await File(config.overlayFilePath ?? 'live_current_track.txt').writeAsString('${track.artist.toUpperCase()} — ${track.title.toUpperCase()}', encoding: utf8, flush: true);
      return const _DispatchOutcome(succeeded: true);
    } catch (_) { return const _DispatchOutcome(succeeded: false, failureCode: ServiceFailureCode.writeFailed); }
  }

  static _DispatchOutcome _interpretHttpResponse(http.Response response) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) return const _DispatchOutcome(succeeded: true);
    final code = status == 401 || status == 403 ? ServiceFailureCode.unauthorized : status == 429 ? ServiceFailureCode.rateLimited : status == 400 || status == 404 ? ServiceFailureCode.invalidConfiguration : status >= 500 ? ServiceFailureCode.unavailable : ServiceFailureCode.unknown;
    return _DispatchOutcome(succeeded: false, failureCode: code);
  }
  static bool _isRetryableCode(ServiceFailureCode code) => code == ServiceFailureCode.timeout || code == ServiceFailureCode.offline || code == ServiceFailureCode.unavailable || code == ServiceFailureCode.rateLimited;
  static ServiceFailureCode _mapExceptionToFailureCode(Object error) {
    if (error is TimeoutException) return ServiceFailureCode.timeout;
    if (error is SocketException) return ServiceFailureCode.offline;
    if (error is FileSystemException) return ServiceFailureCode.writeFailed;
    return ServiceFailureCode.unavailable;
  }
  void _emitStatus(ServiceStatus status) { if (!_statusController.isClosed) _statusController.add(status); }
  void _emitResult(BroadcastAdapterResult result) { if (!_resultController.isClosed) _resultController.add(result); }
  Future<void> dispose() async {
    await _fingerprintSub.cancel();
    if (_shouldCloseClient) _client.close();
    await _statusController.close();
    await _resultController.close();
  }
}

class _DispatchOutcome {
  const _DispatchOutcome({required this.succeeded, this.failureCode});
  final bool succeeded;
  final ServiceFailureCode? failureCode;
}
