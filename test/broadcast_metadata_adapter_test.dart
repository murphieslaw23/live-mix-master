import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:live_mix_master/services/broadcast_metadata_adapter.dart';
import 'package:live_mix_master/services/fingerprint_service.dart';
import 'package:live_mix_master/services/reliability_models.dart';

class MockHttpClient extends http.BaseClient {
  MockHttpClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request) handler;
  final List<http.BaseRequest> recordedRequests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    recordedRequests.add(request);
    return handler(request);
  }
}

http.StreamedResponse jsonResponse(int statusCode, Object? body) {
  final encoded = utf8.encode(jsonEncode(body));
  return http.StreamedResponse(
    Stream.value(encoded),
    statusCode,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

http.StreamedResponse textResponse(int statusCode, String text) {
  final encoded = utf8.encode(text);
  return http.StreamedResponse(
    Stream.value(encoded),
    statusCode,
    headers: {'content-type': 'text/plain; charset=utf-8'},
  );
}

void main() {
  group('BroadcastMetadataAdapter Contract Tests', () {
    late Directory tempDir;
    late StreamController<IdentifiedTrack> fingerprintController;

    final testTrack = IdentifiedTrack(
      artist: 'System Corrupt',
      title: 'Tekno Total 2026',
      release: 'SYCO EP 01',
      acoustId: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
      confidence: 0.95,
      detectedAt: DateTime.utc(2026, 9, 9, 10, 0),
      sessionOffset: const Duration(minutes: 5, seconds: 20),
    );

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('lmm_broadcast_test_');
      fingerprintController = StreamController<IdentifiedTrack>.broadcast();
    });

    tearDown(() async {
      await fingerprintController.close();
      await tempDir.delete(recursive: true);
    });

    group('Icecast 2 Protocol', () {
      test('dispatches GET to /admin/metadata with Basic Auth and UTF-8 query params', () async {
        late MockHttpClient client;
        client = MockHttpClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/admin/metadata');
          expect(request.url.queryParameters['mount'], '/live');
          expect(request.url.queryParameters['mode'], 'updinfo');
          expect(request.url.queryParameters['song'], 'System Corrupt - Tekno Total 2026');
          expect(request.url.queryParameters['charset'], 'UTF-8');
          final authHeader = request.headers['authorization'] ?? request.headers['Authorization'];
          expect(authHeader, 'Basic ' + base64Encode(utf8.encode('source:hackme')));
          return textResponse(200, 'Mountpoint updated');
        });

        final adapter = BroadcastMetadataAdapter(
          config: const BroadcastServerConfig(
            protocol: BroadcastProtocol.icecast,
            host: 'stream.syco23.org',
            port: 8000,
            mountPoint: '/live',
            adminUser: 'source',
            adminPassword: 'hackme',
          ),
          fingerprintStream: fingerprintController.stream,
          httpClient: client,
        );

        expect(adapter.safeEndpointIdentity, 'http://stream.syco23.org:8000/live');
        expect(adapter.safeEndpointIdentity, isNot(contains('hackme')));

        final statusFuture = adapter.onStatus.where((s) => s.state == ServiceOperationState.succeeded).first;
        final result = await adapter.sendMetadata(testTrack);

        expect(result.succeeded, isTrue);
        expect(result.attemptCount, 1);
        expect((await statusFuture).state, ServiceOperationState.succeeded);
        await adapter.dispose();
      });

      test('401 Unauthorized emits terminal unauthorized failure and redacts credentials', () async {
        final client = MockHttpClient((request) async => textResponse(401, 'Unauthorized'));

        final adapter = BroadcastMetadataAdapter(
          config: const BroadcastServerConfig(
            protocol: BroadcastProtocol.icecast,
            host: 'stream.syco23.org',
            port: 8000,
            mountPoint: '/live',
            adminUser: 'source',
            adminPassword: 'secret-pass',
          ),
          fingerprintStream: fingerprintController.stream,
          httpClient: client,
        );

        final statusFuture = adapter.onStatus.where((s) => s.state == ServiceOperationState.failed).first;
        final result = await adapter.sendMetadata(testTrack);

        expect(result.succeeded, isFalse);
        expect(result.failureCode, ServiceFailureCode.unauthorized);
        expect(result.diagnostic, isNot(contains('secret-pass')));
        final status = await statusFuture;
        expect(status.failureCode, ServiceFailureCode.unauthorized);
        await adapter.dispose();
      });

      test('retries on 503 and succeeds on second attempt', () async {
        int attempts = 0;
        final client = MockHttpClient((request) async {
          attempts++;
          if (attempts == 1) {
            return textResponse(503, 'Server Busy');
          }
          return textResponse(200, 'OK');
        });

        final delays = <Duration>[];
        final adapter = BroadcastMetadataAdapter(
          config: const BroadcastServerConfig(
            protocol: BroadcastProtocol.icecast,
            host: 'stream.syco23.org',
            port: 8000,
            maxRetries: 2,
            initialBackoff: const Duration(milliseconds: 10),
          ),
          fingerprintStream: fingerprintController.stream,
          httpClient: client,
          sleeper: (d) async => delays.add(d),
        );

        final result = await adapter.sendMetadata(testTrack);
        expect(result.succeeded, isTrue);
        expect(result.attemptCount, 2);
        expect(attempts, 2);
        expect(delays, hasLength(1));
        await adapter.dispose();
      });
    });

    group('SHOUTcast DNAS Protocol', () {
      test('dispatches GET to /admin.cgi and safe endpoint redacts pass parameter', () async {
        late MockHttpClient client;
        client = MockHttpClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/admin.cgi');
          expect(request.url.queryParameters['mode'], 'updinfo');
          expect(request.url.queryParameters['pass'], 'shoutpass123');
          expect(request.url.queryParameters['song'], 'System Corrupt - Tekno Total 2026');
          return textResponse(200, 'OK');
        });

        final adapter = BroadcastMetadataAdapter(
          config: const BroadcastServerConfig(
            protocol: BroadcastProtocol.shoutcast,
            host: 'shout.syco23.org',
            port: 8004,
            adminPassword: 'shoutpass123',
          ),
          fingerprintStream: fingerprintController.stream,
          httpClient: client,
        );

        expect(adapter.safeEndpointIdentity, 'http://shout.syco23.org:8004/admin.cgi');
        expect(adapter.safeEndpointIdentity, isNot(contains('shoutpass123')));

        final result = await adapter.sendMetadata(testTrack);
        expect(result.succeeded, isTrue);
        await adapter.dispose();
      });
    });

    group('Webhook Protocol', () {
      test('posts typed JSON payload with track metadata', () async {
        late MockHttpClient client;
        client = MockHttpClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.toString(), 'https://api.syco23.org/webhook/tracks?token=abc');
          expect(request, isA<http.Request>());
          final httpRequest = request as http.Request;
          final bodyJson = jsonDecode(httpRequest.body) as Map<String, dynamic>;
          expect(bodyJson['event'], 'track_change');
          expect(bodyJson['artist'], 'System Corrupt');
          expect(bodyJson['title'], 'Tekno Total 2026');
          expect(bodyJson['confidence'], 0.95);
          expect(bodyJson['sessionOffsetMs'], 320000);
          return jsonResponse(200, {'ok': true});
        });

        final adapter = BroadcastMetadataAdapter(
          config: BroadcastServerConfig(
            protocol: BroadcastProtocol.webhook,
            webhookUrl: Uri.parse('https://api.syco23.org/webhook/tracks?token=abc'),
          ),
          fingerprintStream: fingerprintController.stream,
          httpClient: client,
        );

        expect(adapter.safeEndpointIdentity, 'https://api.syco23.org/webhook/tracks');
        expect(adapter.safeEndpointIdentity, isNot(contains('token=abc')));

        final result = await adapter.sendMetadata(testTrack);
        expect(result.succeeded, isTrue);
        await adapter.dispose();
      });

      test('HTTP 429 triggers retry with rateLimited status', () async {
        int attempts = 0;
        final client = MockHttpClient((request) async {
          attempts++;
          return textResponse(429, 'Too Many Requests');
        });

        final retryStatuses = <ServiceStatus>[];
        final adapter = BroadcastMetadataAdapter(
          config: BroadcastServerConfig(
            protocol: BroadcastProtocol.webhook,
            webhookUrl: Uri.parse('https://api.syco23.org/webhook'),
            maxRetries: 2,
            initialBackoff: const Duration(milliseconds: 5),
          ),
          fingerprintStream: fingerprintController.stream,
          httpClient: client,
          sleeper: (_) async {},
        );

        final sub = adapter.onStatus.listen((status) {
          if (status.state == ServiceOperationState.retrying) {
            retryStatuses.add(status);
          }
        });

        final result = await adapter.sendMetadata(testTrack);
        expect(result.succeeded, isFalse);
        expect(result.failureCode, ServiceFailureCode.rateLimited);
        expect(attempts, 3);
        expect(retryStatuses.length, 2);
        expect(retryStatuses.first.failureCode, ServiceFailureCode.rateLimited);

        await sub.cancel();
        await adapter.dispose();
      });

      test('missing webhookUrl emits invalidConfiguration', () async {
        final adapter = BroadcastMetadataAdapter(
          config: const BroadcastServerConfig(
            protocol: BroadcastProtocol.webhook,
            webhookUrl: null,
          ),
          fingerprintStream: fingerprintController.stream,
        );

        final result = await adapter.sendMetadata(testTrack);
        expect(result.succeeded, isFalse);
        expect(result.failureCode, ServiceFailureCode.invalidConfiguration);
        await adapter.dispose();
      });
    });

    group('OBS / Local Text Overlay Protocol', () {
      test('writes uppercase UTF-8 artist and title to target text file', () async {
        final overlayFile = File('${tempDir.path}/live_now.txt');

        final adapter = BroadcastMetadataAdapter(
          config: BroadcastServerConfig(
            protocol: BroadcastProtocol.obsHttpOverlay,
            overlayFilePath: overlayFile.path,
          ),
          fingerprintStream: fingerprintController.stream,
        );

        expect(adapter.safeEndpointIdentity, 'file://${overlayFile.path}');

        final result = await adapter.sendMetadata(testTrack);
        expect(result.succeeded, isTrue);
        expect(await overlayFile.exists(), isTrue);

        final content = await overlayFile.readAsString();
        expect(content, 'SYSTEM CORRUPT — TEKNO TOTAL 2026');
        await adapter.dispose();
      });
    });

    group('Credential and Secret Redaction', () {
      test('redactBroadcastDiagnostic strips tokens, passwords, and basic auth', () {
        const raw = 'Failed request: GET /admin.cgi?mode=updinfo&pass=superSecret123 Basic dXNlcjpwYXNz Authorization: Bearer abc-xyz';
        final redacted = redactBroadcastDiagnostic(raw);
        expect(redacted, isNot(contains('superSecret123')));
        expect(redacted, isNot(contains('dXNlcjpwYXNz')));
        expect(redacted, isNot(contains('abc-xyz')));
        expect(redacted, contains('pass=[REDACTED]'));
        expect(redacted, contains('Basic [REDACTED]'));
        expect(redacted, contains('Bearer [REDACTED]'));
      });
    });
  });
}
