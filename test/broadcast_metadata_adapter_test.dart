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
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  final recordedRequests = <http.BaseRequest>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) { recordedRequests.add(request); return handler(request); }
}
http.StreamedResponse textResponse(int code, String body) => http.StreamedResponse(Stream.value(utf8.encode(body)), code, headers: {'content-type': 'text/plain; charset=utf-8'});
http.StreamedResponse jsonResponse(int code, Object? body) => textResponse(code, jsonEncode(body));

void main() {
  late Directory directory;
  late StreamController<IdentifiedTrack> tracks;
  final track = IdentifiedTrack(artist: 'System Corrupt', title: 'Tekno Total 2026', release: 'SYCO EP 01', acoustId: 'fixture-id', confidence: .95, detectedAt: DateTime.utc(2026, 9, 9, 10), sessionOffset: const Duration(minutes: 5, seconds: 20));
  setUp(() async { directory = await Directory.systemTemp.createTemp('lmm_broadcast_test_'); tracks = StreamController<IdentifiedTrack>.broadcast(); });
  tearDown(() async { await tracks.close(); await directory.delete(recursive: true); });
  void expectIdentity(BroadcastMetadataAdapter adapter) {
    expect(adapter.safeEndpointIdentity, matches(RegExp('^${adapter.config.protocol.name}:destination-[0-9]+\$')));
  }

  test('dispatches GET to /admin/metadata with Basic Auth and UTF-8 query params', () async {
    final client = MockHttpClient((request) async {
      expect(request.method, 'GET'); expect(request.url.path, '/admin/metadata');
      expect(request.url.queryParameters['mount'], '/live'); expect(request.url.queryParameters['mode'], 'updinfo');
      expect(request.url.queryParameters['song'], 'System Corrupt - Tekno Total 2026'); expect(request.url.queryParameters['charset'], 'UTF-8');
      expect(request.headers['authorization'] ?? request.headers['Authorization'], 'Basic ${base64Encode(utf8.encode('source:hackme'))}');
      return textResponse(200, 'Mountpoint updated');
    });
    final adapter = BroadcastMetadataAdapter(config: const BroadcastServerConfig(protocol: BroadcastProtocol.icecast, host: 'stream.syco23.org', adminUser: 'source', adminPassword: 'hackme'), fingerprintStream: tracks.stream, httpClient: client);
    expectIdentity(adapter); expect(adapter.safeEndpointIdentity, isNot(contains('hackme')));
    final success = adapter.onStatus.where((s) => s.state == ServiceOperationState.succeeded).first;
    final result = await adapter.sendMetadata(track); expect(result.succeeded, isTrue); expect(result.attemptCount, 1); expect((await success).state, ServiceOperationState.succeeded);
    await adapter.dispose();
  });
  test('401 Unauthorized emits terminal unauthorized failure and redacts credentials', () async {
    final client = MockHttpClient((_) async => textResponse(401, 'Unauthorized'));
    final adapter = BroadcastMetadataAdapter(config: const BroadcastServerConfig(protocol: BroadcastProtocol.icecast, host: 'stream.syco23.org', adminUser: 'source', adminPassword: 'secret-pass'), fingerprintStream: tracks.stream, httpClient: client);
    final failure = adapter.onStatus.where((s) => s.state == ServiceOperationState.failed).first;
    final result = await adapter.sendMetadata(track); expect(result.succeeded, isFalse); expect(result.failureCode, ServiceFailureCode.unauthorized); expect(result.diagnostic, isNot(contains('secret-pass'))); expect((await failure).failureCode, ServiceFailureCode.unauthorized); expect(client.recordedRequests, hasLength(1));
    await adapter.dispose();
  });
  test('retries on 503 and succeeds on second attempt', () async {
    var attempts = 0; final delays = <Duration>[];
    final client = MockHttpClient((_) async => textResponse(++attempts == 1 ? 503 : 200, 'fixture'));
    final adapter = BroadcastMetadataAdapter(config: const BroadcastServerConfig(protocol: BroadcastProtocol.icecast, host: 'stream.syco23.org', initialBackoff: Duration(milliseconds: 10)), fingerprintStream: tracks.stream, httpClient: client, sleeper: (d) async { delays.add(d); });
    final result = await adapter.sendMetadata(track); expect(result.succeeded, isTrue); expect(result.attemptCount, 2); expect(attempts, 2); expect(delays, [const Duration(milliseconds: 10)]);
    await adapter.dispose();
  });
  test('dispatches GET to /admin.cgi and safe endpoint redacts pass parameter', () async {
    final client = MockHttpClient((request) async {
      expect(request.method, 'GET'); expect(request.url.path, '/admin.cgi'); expect(request.url.port, 8004);
      expect(request.url.queryParameters['mode'], 'updinfo'); expect(request.url.queryParameters['pass'], 'shoutpass123'); expect(request.url.queryParameters['song'], 'System Corrupt - Tekno Total 2026');
      return textResponse(200, 'OK');
    });
    final adapter = BroadcastMetadataAdapter(config: const BroadcastServerConfig(protocol: BroadcastProtocol.shoutcast, host: 'shout.syco23.org', port: 8004, adminPassword: 'shoutpass123'), fingerprintStream: tracks.stream, httpClient: client);
    expectIdentity(adapter); expect(adapter.safeEndpointIdentity, isNot(contains('shoutpass123'))); expect((await adapter.sendMetadata(track)).succeeded, isTrue); await adapter.dispose();
  });
  test('posts typed JSON payload with track metadata', () async {
    final client = MockHttpClient((request) async {
      expect(request.method, 'POST'); expect(request.url.toString(), 'https://api.syco23.org/webhook/tracks?token=abc'); expect(request, isA<http.Request>());
      final body = jsonDecode((request as http.Request).body) as Map<String, dynamic>;
      expect(body['event'], 'track_change'); expect(body['artist'], 'System Corrupt'); expect(body['title'], 'Tekno Total 2026'); expect(body['release'], 'SYCO EP 01'); expect(body['confidence'], .95); expect(body['sessionOffsetMs'], 320000); expect(body['detectedAt'], '2026-09-09T10:00:00.000Z');
      return jsonResponse(200, {'ok': true});
    });
    final adapter = BroadcastMetadataAdapter(config: BroadcastServerConfig(protocol: BroadcastProtocol.webhook, webhookUrl: Uri.parse('https://api.syco23.org/webhook/tracks?token=abc')), fingerprintStream: tracks.stream, httpClient: client);
    expectIdentity(adapter); expect(adapter.safeEndpointIdentity, isNot(contains('token=abc'))); expect((await adapter.sendMetadata(track)).succeeded, isTrue); await adapter.dispose();
  });
  test('HTTP 429 triggers retry with rateLimited status', () async {
    final client = MockHttpClient((_) async => textResponse(429, 'Too Many Requests')); final statuses = <ServiceStatus>[];
    final adapter = BroadcastMetadataAdapter(config: BroadcastServerConfig(protocol: BroadcastProtocol.webhook, webhookUrl: Uri.parse('https://api.syco23.org/webhook'), initialBackoff: const Duration(milliseconds: 5)), fingerprintStream: tracks.stream, httpClient: client, sleeper: (_) async {});
    final sub = adapter.onStatus.listen(statuses.add); final result = await adapter.sendMetadata(track);
    expect(result.succeeded, isFalse); expect(result.failureCode, ServiceFailureCode.rateLimited); expect(client.recordedRequests, hasLength(3));
    final retrying = statuses.where((s) => s.state == ServiceOperationState.retrying).toList(); expect(retrying, hasLength(2)); expect(retrying.first.failureCode, ServiceFailureCode.rateLimited);
    await sub.cancel(); await adapter.dispose();
  });
  test('missing webhookUrl emits invalidConfiguration', () async {
    final client = MockHttpClient((_) async => textResponse(200, 'unexpected'));
    final adapter = BroadcastMetadataAdapter(config: const BroadcastServerConfig(protocol: BroadcastProtocol.webhook), fingerprintStream: tracks.stream, httpClient: client);
    final result = await adapter.sendMetadata(track); expect(result.succeeded, isFalse); expect(result.failureCode, ServiceFailureCode.invalidConfiguration); expect(result.attemptCount, 0); expect(client.recordedRequests, isEmpty); expectIdentity(adapter); await adapter.dispose();
  });
  test('writes uppercase UTF-8 artist and title to target text file', () async {
    final file = File('${directory.path}/live_now.txt');
    final adapter = BroadcastMetadataAdapter(config: BroadcastServerConfig(protocol: BroadcastProtocol.obsHttpOverlay, overlayFilePath: file.path), fingerprintStream: tracks.stream);
    expectIdentity(adapter); expect((await adapter.sendMetadata(track)).succeeded, isTrue); expect(await file.exists(), isTrue); expect(await file.readAsString(), 'SYSTEM CORRUPT — TEKNO TOTAL 2026'); await adapter.dispose();
  });
  test('redactBroadcastDiagnostic strips tokens, passwords, and basic auth', () {
    const raw = 'GET /admin.cgi?pass=superSecret123 Basic dXNlcjpwYXNz token=my-token Bearer abc-xyz';
    final redacted = redactBroadcastDiagnostic(raw);
    for (final secret in ['superSecret123', 'dXNlcjpwYXNz', 'my-token', 'abc-xyz']) { expect(redacted, isNot(contains(secret))); }
    for (final marker in ['pass=[REDACTED]', 'Basic [REDACTED]', 'token=[REDACTED]', 'Bearer [REDACTED]']) { expect(redacted, contains(marker)); }
  });

  for (final raw in ['Authorization: Basic dXNlcjpwYXNz', 'aUtHoRiZaTiOn: bAsIc dXNlcjpwYXNz', 'Proxy-Authorization: Basic dXNlcjpwYXNz', 'Authorization: Bearer secret-token', 'password="secret phrase" token=secret-token', "pass='secret phrase'", 'https://user:secret-token@example.test/private/secret-path?token=secret-token#secret-fragment']) {
    test('A1 shared and broadcast sanitizers remove secrets from $raw', () {
      final shared = redactDiagnostic(raw); expect(redactBroadcastDiagnostic(raw), shared);
      for (final secret in ['dXNlcjpwYXNz', 'secret-token', 'secret phrase', 'secret-path', 'secret-fragment']) { expect(shared, isNot(contains(secret))); }
      expect(redactDiagnostic(shared), shared);
    });
  }
  test('A1 diagnostics normalize control characters and fail closed on oversized text', () {
    expect(redactDiagnostic('error\r\nforged\tentry\u2028next'), 'error  forged entry next');
    expect(redactDiagnostic(List.filled(2049, 'x').join()), '[REDACTED: diagnostic too long]');
  });
  for (final protocol in BroadcastProtocol.values) {
    test('A2 ${protocol.name} identity is stable opaque and independent of destination', () async {
      final adapter = BroadcastMetadataAdapter(config: BroadcastServerConfig(protocol: protocol, host: 'secret-host.test', mountPoint: '/secret-mount', adminUser: 'secret-user', adminPassword: 'secret-password', webhookUrl: Uri.parse('https://secret-user:secret-password@secret-host.test/secret-path?token=secret-token#secret-fragment'), overlayFilePath: '${directory.path}/secret-path.txt'), fingerprintStream: tracks.stream);
      expectIdentity(adapter); final identity = adapter.safeEndpointIdentity; expect(adapter.safeEndpointIdentity, identity);
      for (final secret in ['secret-host', 'secret-mount', 'secret-user', 'secret-password', 'secret-path', 'secret-token', 'secret-fragment', directory.path]) { expect(identity, isNot(contains(secret))); }
      await adapter.dispose();
    });
  }
  test('A2 different adapters receive different destination IDs', () async {
    final a = BroadcastMetadataAdapter(config: const BroadcastServerConfig(protocol: BroadcastProtocol.webhook), fingerprintStream: tracks.stream);
    final b = BroadcastMetadataAdapter(config: const BroadcastServerConfig(protocol: BroadcastProtocol.webhook), fingerprintStream: tracks.stream);
    expect(a.safeEndpointIdentity, isNot(b.safeEndpointIdentity)); await a.dispose(); await b.dispose();
  });
  test('A1 client exceptions do not leak through retries statuses or results', () async {
    const leak = 'https://secret-user:secret-password@example.test/secret-path?token=secret-token Authorization: Basic dXNlcjpwYXNz BODY secret-body';
    final client = MockHttpClient((_) async { throw http.ClientException(leak); });
    final adapter = BroadcastMetadataAdapter(config: BroadcastServerConfig(protocol: BroadcastProtocol.webhook, webhookUrl: Uri.parse('https://example.test/secret-path')), fingerprintStream: tracks.stream, httpClient: client, sleeper: (_) async {});
    final statuses = <ServiceStatus>[]; final results = <BroadcastAdapterResult>[];
    final statusSub = adapter.onStatus.listen(statuses.add); final resultSub = adapter.onResult.listen(results.add);
    final result = await adapter.sendMetadata(track); expect(result.succeeded, isFalse); expect(result.attemptCount, 3); expect(result.diagnosticCode, 'broadcast.unavailable'); expect(results, hasLength(1));
    final exposed = [...statuses.map((s) => s.message ?? ''), ...results.map((r) => '${r.safeEndpointIdentity} ${r.diagnostic} ${r.diagnosticCode}')].join(' ');
    for (final secret in ['secret-user', 'secret-password', 'secret-path', 'secret-token', 'dXNlcjpwYXNz', 'secret-body']) { expect(exposed, isNot(contains(secret))); }
    expect(statuses.where((s) => s.state == ServiceOperationState.retrying), hasLength(2));
    await statusSub.cancel(); await resultSub.cancel(); await adapter.dispose();
  });
  test('A1 provider response body is never exposed in auth failure', () async {
    final adapter = BroadcastMetadataAdapter(config: const BroadcastServerConfig(protocol: BroadcastProtocol.icecast), fingerprintStream: tracks.stream, httpClient: MockHttpClient((_) async => textResponse(403, 'secret-response-body')));
    final result = await adapter.sendMetadata(track); expect(result.diagnostic, 'Broadcast authentication failed.'); expect(result.diagnosticCode, 'broadcast.unauthorized'); expect(result.diagnostic, isNot(contains('secret-response-body'))); await adapter.dispose();
  });
  test('A1 overlay failures do not expose filesystem paths', () async {
    final adapter = BroadcastMetadataAdapter(config: BroadcastServerConfig(protocol: BroadcastProtocol.obsHttpOverlay, overlayFilePath: '${directory.path}/secret-missing-parent/secret-file.txt'), fingerprintStream: tracks.stream);
    final statuses = <ServiceStatus>[]; final sub = adapter.onStatus.listen(statuses.add);
    final result = await adapter.sendMetadata(track); expect(result.failureCode, ServiceFailureCode.writeFailed); expect(result.diagnostic, 'Local overlay could not be updated.');
    final exposed = '${result.safeEndpointIdentity} ${result.diagnostic} ${statuses.map((s) => s.message).join(' ')}'; expect(exposed, isNot(contains(directory.path))); expect(exposed, isNot(contains('secret-file')));
    await sub.cancel(); await adapter.dispose();
  });
}
