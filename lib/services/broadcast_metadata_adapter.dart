import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'fingerprint_service.dart';
import 'reliability_models.dart';

/// Broadcast Metadata Adapter for LiveMixMaster
///
/// Pushes newly identified track metadata (Artist — Title)
/// to Icecast/SHOUTcast servers, OBS WebSocket/HTTP overlays,
/// and external internet radio syndication APIs behind a typed reliability boundary.

enum BroadcastProtocol { icecast, shoutcast, webhook, obsHttpOverlay }

class BroadcastServerConfig {
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

  const BroadcastServerConfig({
    required this.protocol,
    this.host = 'localhost',
    this.port = 8000,
    this.mountPoint = '/live',
    this.adminUser = 'admin',
    this.adminPassword = '',
    this.webhookUrl,
    this.timeout = const Duration(seconds: 4),
    this.maxRetries = 2,
    this.initialBackoff = const Duration(milliseconds: 100),
    this.overlayFilePath,
  });

  ServiceFailureCode? get validationFailure {
    switch (protocol) {
      case BroadcastProtocol.icecast:
      case BroadcastProtocol.shoutcast:
        if (host.trim().isEmpty || port <= 0 || port > 65535) {
          return ServiceFailureCode.invalidConfiguration;
        }
        break;
      case BroadcastProtocol.webhook:
        if (webhookUrl == null || !webhookUrl!.hasScheme || webhookUrl!.host.isEmpty) {
          return ServiceFailureCode.invalidConfiguration;
        }
        break;
      case BroadcastProtocol.obsHttpOverlay:
        break;
    }
    return null;
  }
}

class BroadcastAdapterResult {
  final BroadcastProtocol protocol;
  final int attemptCount;
  final String safeEndpointIdentity;
  final bool succeeded;
  final ServiceFailureCode? failureCode;
  final String? diagnostic;

  const BroadcastAdapterResult({
    required this.protocol,
    required this.attemptCount,
    required this.safeEndpointIdentity,
    required this.succeeded,
    this.failureCode,
    this.diagnostic,
  });
}

String redactBroadcastDiagnostic(String value) {
  var sanitized = redactDiagnostic(value);
  sanitized = sanitized.replaceAll(
    RegExp(r'Basic\s+[A-Za-z0-9+/=]+', caseSensitive: false),
    'Basic [REDACTED]',
  );
  sanitized = sanitized.replaceAllMapped(
    RegExp(r'([?&]pass=)[^&\s]+', caseSensitive: false),
    (match) => '${match.group(1)}[REDACTED]',
  );
  return sanitized;
}

class BroadcastMetadataAdapter {
  final BroadcastServerConfig config;
  final StreamSubscription<IdentifiedTrack>? _fingerprintSub;
  final http.Client _client;
  final bool _shouldCloseClient;
  final Future<void> Function(Duration)? _sleeper;
  final StreamController<ServiceStatus> _statusController;
  final StreamController<BroadcastAdapterResult> _resultController;
  bool _isConnected = false;

  BroadcastMetadataAdapter({
    required this.config,
    required Stream<IdentifiedTrack> fingerprintStream,
    http.Client? httpClient,
    Future<void> Function(Duration)? sleeper,
  })  : _client = httpClient ?? http.Client(),
        _shouldCloseClient = httpClient == null,
        _sleeper = sleeper,
        _statusController = StreamController<ServiceStatus>.broadcast(sync: true),
        _resultController = StreamController<BroadcastAdapterResult>.broadcast(sync: true),
        _fingerprintSub = fingerprintStream.listen(null) {
    _fingerprintSub?.onData(_onTrackDetected);
  }

  bool get isConnected => _isConnected;
  Stream<ServiceStatus> get onStatus => _statusController.stream;
  Stream<BroadcastAdapterResult> get onResult => _resultController.stream;
  String get safeEndpointIdentity => _computeSafeEndpoint(config);

  static String _computeSafeEndpoint(BroadcastServerConfig config) {
    switch (config.protocol) {
      case BroadcastProtocol.icecast:
        final mount = config.mountPoint.startsWith('/') ? config.mountPoint : '/${config.mountPoint}';
        return 'http://${config.host}:${config.port}$mount';
      case BroadcastProtocol.shoutcast:
        return 'http://${config.host}:${config.port}/admin.cgi';
      case BroadcastProtocol.webhook:
        if (config.webhookUrl == null) return 'webhook://invalid';
        return '${config.webhookUrl!.scheme}://${config.webhookUrl!.host}${config.webhookUrl!.hasPort ? ':${config.webhookUrl!.port}' : ''}${config.webhookUrl!.path}';
      case BroadcastProtocol.obsHttpOverlay:
        return 'file://${config.overlayFilePath ?? 'live_current_track.txt'}';
    }
  }

  void _onTrackDetected(IdentifiedTrack track) {
    sendMetadata(track);
  }

  Future<BroadcastAdapterResult> sendMetadata(IdentifiedTrack track) async {
    final validation = config.validationFailure;
    if (validation != null) {
      final diagnostic = 'Invalid configuration for ${config.protocol.name}';
      _emitStatus(ServiceStatus.failed(failureCode: validation, message: diagnostic));
      final result = BroadcastAdapterResult(
        protocol: config.protocol,
        attemptCount: 0,
        safeEndpointIdentity: safeEndpointIdentity,
        succeeded: false,
        failureCode: validation,
        diagnostic: diagnostic,
      );
      _emitResult(result);
      return result;
    }

    final maxAttempts = 1 + config.maxRetries;
    int attempt = 0;
    ServiceFailureCode? lastFailureCode;
    String? lastDiagnostic;

    while (attempt < maxAttempts) {
      attempt++;
      _emitStatus(ServiceStatus.running(attempt: attempt));

      try {
        final outcome = await _executeDispatch(track);
        if (outcome.succeeded) {
          _isConnected = true;
          _emitStatus(const ServiceStatus.succeeded());
          final result = BroadcastAdapterResult(
            protocol: config.protocol,
            attemptCount: attempt,
            safeEndpointIdentity: safeEndpointIdentity,
            succeeded: true,
          );
          _emitResult(result);
          return result;
        }

        lastFailureCode = outcome.failureCode ?? ServiceFailureCode.unknown;
        lastDiagnostic = outcome.diagnostic;

        final isRetryable = _isRetryableCode(lastFailureCode);
        if (!isRetryable || attempt >= maxAttempts) {
          break;
        }

        final backoff = config.initialBackoff * (1 << (attempt - 1));
        final nextRetryAt = DateTime.now().add(backoff);
        _emitStatus(ServiceStatus.retrying(
          failureCode: lastFailureCode,
          attempt: attempt,
          nextRetryAt: nextRetryAt,
          message: lastDiagnostic,
        ));

        if (_sleeper != null) {
          await _sleeper(backoff);
        } else {
          await Future<void>.delayed(backoff);
        }
      } catch (error) {
        lastFailureCode = _mapExceptionToFailureCode(error);
        lastDiagnostic = redactBroadcastDiagnostic(error.toString());

        final isRetryable = _isRetryableCode(lastFailureCode);
        if (!isRetryable || attempt >= maxAttempts) {
          break;
        }

        final backoff = config.initialBackoff * (1 << (attempt - 1));
        final nextRetryAt = DateTime.now().add(backoff);
        _emitStatus(ServiceStatus.retrying(
          failureCode: lastFailureCode,
          attempt: attempt,
          nextRetryAt: nextRetryAt,
          message: lastDiagnostic,
        ));

        if (_sleeper != null) {
          await _sleeper(backoff);
        } else {
          await Future<void>.delayed(backoff);
        }
      }
    }

    _isConnected = false;
    final finalFailureCode = lastFailureCode ?? ServiceFailureCode.unknown;
    _emitStatus(ServiceStatus.failed(
      failureCode: finalFailureCode,
      message: lastDiagnostic,
      attempt: attempt,
    ));

    final failedResult = BroadcastAdapterResult(
      protocol: config.protocol,
      attemptCount: attempt,
      safeEndpointIdentity: safeEndpointIdentity,
      succeeded: false,
      failureCode: finalFailureCode,
      diagnostic: lastDiagnostic,
    );
    _emitResult(failedResult);
    return failedResult;
  }

  Future<_DispatchOutcome> _executeDispatch(IdentifiedTrack track) async {
    final song = '${track.artist} - ${track.title}';
    switch (config.protocol) {
      case BroadcastProtocol.icecast:
        return _dispatchIcecast(song);
      case BroadcastProtocol.shoutcast:
        return _dispatchShoutcast(song);
      case BroadcastProtocol.webhook:
        return _dispatchWebhook(track);
      case BroadcastProtocol.obsHttpOverlay:
        return _dispatchOverlay(track);
    }
  }

  Future<_DispatchOutcome> _dispatchIcecast(String song) async {
    final mount = config.mountPoint.startsWith('/') ? config.mountPoint : '/${config.mountPoint}';
    final uri = Uri(
      scheme: 'http',
      host: config.host,
      port: config.port,
      path: '/admin/metadata',
      queryParameters: {
        'mount': mount,
        'mode': 'updinfo',
        'song': song,
        'charset': 'UTF-8',
      },
    );

    final basicAuth = 'Basic ' + base64Encode(utf8.encode('${config.adminUser}:${config.adminPassword}'));
    try {
      final response = await _client.get(
        uri,
        headers: {'Authorization': basicAuth},
      ).timeout(config.timeout);

      return _interpretHttpResponse(response);
    } on TimeoutException {
      return const _DispatchOutcome(
        succeeded: false,
        failureCode: ServiceFailureCode.timeout,
        diagnostic: 'Icecast request timed out',
      );
    } catch (e) {
      return _DispatchOutcome(
        succeeded: false,
        failureCode: _mapExceptionToFailureCode(e),
        diagnostic: redactBroadcastDiagnostic(e.toString()),
      );
    }
  }

  Future<bool> _updateIcecastMetadata(String song) async {
    final outcome = await _dispatchIcecast(song);
    return outcome.succeeded;
  }

  Future<_DispatchOutcome> _dispatchShoutcast(String song) async {
    final uri = Uri(
      scheme: 'http',
      host: config.host,
      port: config.port,
      path: '/admin.cgi',
      queryParameters: {
        'mode': 'updinfo',
        'pass': config.adminPassword,
        'song': song,
      },
    );

    try {
      final response = await _client.get(uri).timeout(config.timeout);
      return _interpretHttpResponse(response);
    } on TimeoutException {
      return const _DispatchOutcome(
        succeeded: false,
        failureCode: ServiceFailureCode.timeout,
        diagnostic: 'SHOUTcast request timed out',
      );
    } catch (e) {
      return _DispatchOutcome(
        succeeded: false,
        failureCode: _mapExceptionToFailureCode(e),
        diagnostic: redactBroadcastDiagnostic(e.toString()),
      );
    }
  }

  Future<bool> _updateShoutcastMetadata(String song) async {
    final outcome = await _dispatchShoutcast(song);
    return outcome.succeeded;
  }

  Future<_DispatchOutcome> _dispatchWebhook(IdentifiedTrack track) async {
    final url = config.webhookUrl;
    if (url == null) {
      return const _DispatchOutcome(
        succeeded: false,
        failureCode: ServiceFailureCode.invalidConfiguration,
        diagnostic: 'Missing webhook URL',
      );
    }

    final payload = jsonEncode({
      'event': 'track_change',
      'artist': track.artist,
      'title': track.title,
      'release': track.release,
      'confidence': track.confidence,
      'detectedAt': track.detectedAt.toUtc().toIso8601String(),
      'sessionOffsetMs': track.sessionOffset.inMilliseconds,
    });

    try {
      final response = await _client.post(
        url,
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: payload,
      ).timeout(config.timeout);

      return _interpretHttpResponse(response);
    } on TimeoutException {
      return const _DispatchOutcome(
        succeeded: false,
        failureCode: ServiceFailureCode.timeout,
        diagnostic: 'Webhook request timed out',
      );
    } catch (e) {
      return _DispatchOutcome(
        succeeded: false,
        failureCode: _mapExceptionToFailureCode(e),
        diagnostic: redactBroadcastDiagnostic(e.toString()),
      );
    }
  }

  Future<bool> _sendWebhookMetadata(IdentifiedTrack track) async {
    final outcome = await _dispatchWebhook(track);
    return outcome.succeeded;
  }

  Future<_DispatchOutcome> _dispatchOverlay(IdentifiedTrack track) async {
    try {
      final file = File(config.overlayFilePath ?? 'live_current_track.txt');
      await file.writeAsString(
        '${track.artist.toUpperCase()} — ${track.title.toUpperCase()}',
        encoding: utf8,
        flush: true,
      );
      return const _DispatchOutcome(succeeded: true);
    } on FileSystemException catch (e) {
      return _DispatchOutcome(
        succeeded: false,
        failureCode: ServiceFailureCode.writeFailed,
        diagnostic: redactBroadcastDiagnostic(e.message),
      );
    } catch (e) {
      return _DispatchOutcome(
        succeeded: false,
        failureCode: ServiceFailureCode.writeFailed,
        diagnostic: redactBroadcastDiagnostic(e.toString()),
      );
    }
  }

  Future<void> _updateLocalOverlayEndpoint(IdentifiedTrack track) async {
    await _dispatchOverlay(track);
  }

  static _DispatchOutcome _interpretHttpResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return const _DispatchOutcome(succeeded: true);
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      return _DispatchOutcome(
        succeeded: false,
        failureCode: ServiceFailureCode.unauthorized,
        diagnostic: 'Authentication failed with status ${response.statusCode}',
      );
    }
    if (response.statusCode == 429) {
      return const _DispatchOutcome(
        succeeded: false,
        failureCode: ServiceFailureCode.rateLimited,
        diagnostic: 'Endpoint rate limited (HTTP 429)',
      );
    }
    if (response.statusCode == 400 || response.statusCode == 404) {
      return _DispatchOutcome(
        succeeded: false,
        failureCode: ServiceFailureCode.invalidConfiguration,
        diagnostic: 'Server rejected request with status ${response.statusCode}',
      );
    }
    if (response.statusCode >= 500) {
      return _DispatchOutcome(
        succeeded: false,
        failureCode: ServiceFailureCode.unavailable,
        diagnostic: 'Server error with status ${response.statusCode}',
      );
    }
    return _DispatchOutcome(
      succeeded: false,
      failureCode: ServiceFailureCode.unknown,
      diagnostic: 'Unexpected HTTP status: ${response.statusCode}',
    );
  }

  static bool _isRetryableCode(ServiceFailureCode code) {
    switch (code) {
      case ServiceFailureCode.timeout:
      case ServiceFailureCode.offline:
      case ServiceFailureCode.unavailable:
      case ServiceFailureCode.rateLimited:
        return true;
      case ServiceFailureCode.unauthorized:
      case ServiceFailureCode.invalidConfiguration:
      case ServiceFailureCode.malformedResponse:
      case ServiceFailureCode.permissionDenied:
      case ServiceFailureCode.storageFull:
      case ServiceFailureCode.writeFailed:
      case ServiceFailureCode.queueOverflow:
      case ServiceFailureCode.cancelled:
      case ServiceFailureCode.unknown:
        return false;
    }
  }

  static ServiceFailureCode _mapExceptionToFailureCode(Object error) {
    if (error is TimeoutException) return ServiceFailureCode.timeout;
    if (error is SocketException) return ServiceFailureCode.offline;
    if (error is FileSystemException) return ServiceFailureCode.writeFailed;
    return ServiceFailureCode.unavailable;
  }

  void _emitStatus(ServiceStatus status) {
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  void _emitResult(BroadcastAdapterResult result) {
    if (!_resultController.isClosed) {
      _resultController.add(result);
    }
  }

  Future<void> dispose() async {
    await _fingerprintSub?.cancel();
    if (_shouldCloseClient) {
      _client.close();
    }
    await _statusController.close();
    await _resultController.close();
  }
}

class _DispatchOutcome {
  final bool succeeded;
  final ServiceFailureCode? failureCode;
  final String? diagnostic;

  const _DispatchOutcome({
    required this.succeeded,
    this.failureCode,
    this.diagnostic,
  });
}
