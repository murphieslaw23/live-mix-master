import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:live_mix_master/services/broadcast_metadata_adapter.dart';
import 'package:live_mix_master/services/fingerprint_service.dart';
import 'package:live_mix_master/services/reliability_models.dart';

class _CountingClient extends http.BaseClient {
  int calls = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    return http.StreamedResponse(const Stream<List<int>>.empty(), 503);
  }
}

void registerBroadcastConfigValidationTests() {
  group('A5 broadcast configuration validation', () {
    final track = IdentifiedTrack(artist: 'Artist', title: 'Title', acoustId: 'fixture', confidence: .9, detectedAt: DateTime.utc(2026), sessionOffset: Duration.zero);
    final invalid = <({String name, BroadcastServerConfig config, BroadcastValidationIssue issue})>[
      (name: 'negative timeout', config: const BroadcastServerConfig(protocol: BroadcastProtocol.icecast, timeout: Duration(milliseconds: -1)), issue: BroadcastValidationIssue.invalidTimeout),
      (name: 'zero timeout', config: const BroadcastServerConfig(protocol: BroadcastProtocol.icecast, timeout: Duration.zero), issue: BroadcastValidationIssue.invalidTimeout),
      (name: 'excessive timeout', config: const BroadcastServerConfig(protocol: BroadcastProtocol.icecast, timeout: Duration(seconds: 61)), issue: BroadcastValidationIssue.invalidTimeout),
      (name: 'negative retries', config: const BroadcastServerConfig(protocol: BroadcastProtocol.icecast, maxRetries: -1), issue: BroadcastValidationIssue.invalidRetryCount),
      (name: 'excessive retries', config: const BroadcastServerConfig(protocol: BroadcastProtocol.icecast, maxRetries: 6), issue: BroadcastValidationIssue.invalidRetryCount),
      (name: 'negative initial delay', config: const BroadcastServerConfig(protocol: BroadcastProtocol.icecast, initialBackoff: Duration(milliseconds: -1)), issue: BroadcastValidationIssue.invalidBackoff),
      (name: 'zero cap', config: const BroadcastServerConfig(protocol: BroadcastProtocol.icecast, maxBackoff: Duration.zero), issue: BroadcastValidationIssue.invalidBackoff),
      (name: 'excessive cap', config: const BroadcastServerConfig(protocol: BroadcastProtocol.icecast, maxBackoff: Duration(seconds: 31)), issue: BroadcastValidationIssue.invalidBackoff),
      (name: 'initial delay exceeds cap', config: const BroadcastServerConfig(protocol: BroadcastProtocol.icecast, initialBackoff: Duration(seconds: 2), maxBackoff: Duration(seconds: 1)), issue: BroadcastValidationIssue.invalidBackoff),
      (name: 'URL in host', config: const BroadcastServerConfig(protocol: BroadcastProtocol.icecast, host: 'https://secret-host.test/path'), issue: BroadcastValidationIssue.invalidHost),
      (name: 'credentials in host', config: const BroadcastServerConfig(protocol: BroadcastProtocol.shoutcast, host: 'user:secret-password@host.test'), issue: BroadcastValidationIssue.invalidHost),
      (name: 'whitespace host', config: const BroadcastServerConfig(protocol: BroadcastProtocol.icecast, host: ' host.test'), issue: BroadcastValidationIssue.invalidHost),
      (name: 'malformed IPv4', config: const BroadcastServerConfig(protocol: BroadcastProtocol.icecast, host: '999.1.1.1'), issue: BroadcastValidationIssue.invalidHost),
      (name: 'malformed IPv6', config: const BroadcastServerConfig(protocol: BroadcastProtocol.icecast, host: '[not:ipv6]'), issue: BroadcastValidationIssue.invalidHost),
      (name: 'zero port', config: const BroadcastServerConfig(protocol: BroadcastProtocol.icecast, port: 0), issue: BroadcastValidationIssue.invalidPort),
      (name: 'excessive port', config: const BroadcastServerConfig(protocol: BroadcastProtocol.shoutcast, port: 65536), issue: BroadcastValidationIssue.invalidPort),
      (name: 'empty mount', config: const BroadcastServerConfig(protocol: BroadcastProtocol.icecast, mountPoint: ''), issue: BroadcastValidationIssue.invalidMount),
      (name: 'mount query', config: const BroadcastServerConfig(protocol: BroadcastProtocol.icecast, mountPoint: '/live?token=secret-token'), issue: BroadcastValidationIssue.invalidMount),
      (name: 'mount newline', config: const BroadcastServerConfig(protocol: BroadcastProtocol.icecast, mountPoint: '/live\nsecret'), issue: BroadcastValidationIssue.invalidMount),
      (name: 'missing webhook', config: const BroadcastServerConfig(protocol: BroadcastProtocol.webhook), issue: BroadcastValidationIssue.invalidWebhook),
      (name: 'unsupported scheme', config: BroadcastServerConfig(protocol: BroadcastProtocol.webhook, webhookUrl: Uri.parse('ftp://example.test/path')), issue: BroadcastValidationIssue.invalidWebhook),
      (name: 'HTTP without opt-in', config: BroadcastServerConfig(protocol: BroadcastProtocol.webhook, webhookUrl: Uri.parse('http://localhost/path')), issue: BroadcastValidationIssue.invalidWebhook),
      (name: 'URL credentials', config: BroadcastServerConfig(protocol: BroadcastProtocol.webhook, webhookUrl: Uri.parse('https://user:secret-password@example.test/path')), issue: BroadcastValidationIssue.invalidWebhook),
      (name: 'URL fragment', config: BroadcastServerConfig(protocol: BroadcastProtocol.webhook, webhookUrl: Uri.parse('https://example.test/path#secret-fragment')), issue: BroadcastValidationIssue.invalidWebhook),
      (name: 'URL zero port', config: BroadcastServerConfig(protocol: BroadcastProtocol.webhook, webhookUrl: Uri.parse('https://example.test:0/path')), issue: BroadcastValidationIssue.invalidWebhook),
      (name: 'empty overlay path', config: const BroadcastServerConfig(protocol: BroadcastProtocol.obsHttpOverlay, overlayFilePath: '   '), issue: BroadcastValidationIssue.invalidOverlayPath),
      (name: 'NUL overlay path', config: BroadcastServerConfig(protocol: BroadcastProtocol.obsHttpOverlay, overlayFilePath: 'secret-path${String.fromCharCode(0)}'), issue: BroadcastValidationIssue.invalidOverlayPath),
    ];
    for (final item in invalid) {
      test('${item.name} fails before any dispatch', () async {
        expect(item.config.validationIssue, item.issue);
        final client = _CountingClient(); var writes = 0; var delays = 0;
        final adapter = BroadcastMetadataAdapter(config: item.config, fingerprintStream: const Stream<IdentifiedTrack>.empty(), httpClient: client, sleeper: (_) async { delays++; }, overlayWriter: (_, __) async { writes++; });
        final statuses = <ServiceStatus>[]; final results = <BroadcastAdapterResult>[];
        final sub = adapter.onStatus.listen(statuses.add); final resultSub = adapter.onResult.listen(results.add);
        final result = await adapter.sendMetadata(track);
        expect(result.failureCode, ServiceFailureCode.invalidConfiguration); expect(result.attemptCount, 0); expect(result.succeeded, isFalse);
        expect(client.calls, 0); expect(writes, 0); expect(delays, 0);
        expect(statuses, hasLength(1)); expect(statuses.single.state, ServiceOperationState.failed); expect(results, hasLength(1));
        final exposed = '${result.safeEndpointIdentity} ${result.diagnostic} ${statuses.single.message}';
        for (final secret in ['secret-password', 'secret-token', 'secret-fragment', 'secret-path', 'secret-host']) { expect(exposed, isNot(contains(secret))); }
        await sub.cancel(); await resultSub.cancel(); await adapter.dispose();
      });
    }
    for (final host in ['localhost', 'stream.example.test', '192.0.2.1', '::1', '[2001:db8::1]']) {
      test('valid host syntax $host builds a metadata URI without DNS', () {
        final config = BroadcastServerConfig(protocol: BroadcastProtocol.icecast, host: host, mountPoint: 'live', timeout: const Duration(seconds: 60), maxRetries: 5);
        expect(config.validationIssue, isNull); final uri = config.buildMetadataUri('Björk & Artist - Title?');
        expect(uri.path, '/admin/metadata'); expect(uri.queryParameters['mount'], '/live'); expect(uri.queryParameters['song'], 'Björk & Artist - Title?'); expect(uri.queryParameters['charset'], 'UTF-8');
      });
    }
    test('HTTPS is accepted and HTTP requires explicit opt-in', () {
      expect(BroadcastServerConfig(protocol: BroadcastProtocol.webhook, webhookUrl: Uri.parse('https://example.test/a?token=fixture')).validationIssue, isNull);
      final local = BroadcastServerConfig(protocol: BroadcastProtocol.webhook, webhookUrl: Uri.parse('http://localhost:8000/a'), allowHttpWebhook: true);
      expect(local.validationIssue, isNull); expect(local.buildMetadataUri('unused').scheme, 'http');
    });
    test('SHOUTcast URI preserves password placement and song encoding', () {
      const config = BroadcastServerConfig(protocol: BroadcastProtocol.shoutcast, adminPassword: 'fixture & pass', port: 65535);
      final uri = config.buildMetadataUri('A & B'); expect(uri.path, '/admin.cgi'); expect(uri.port, 65535); expect(uri.queryParameters['pass'], 'fixture & pass'); expect(uri.queryParameters['song'], 'A & B');
    });
    test('retry delay grows exponentially and never exceeds cap', () {
      const config = BroadcastServerConfig(protocol: BroadcastProtocol.icecast, maxRetries: 5, initialBackoff: Duration(seconds: 10));
      expect([for (var i = 1; i <= 5; i++) config.retryDelay(i).inSeconds], [10, 20, 30, 30, 30]);
      expect(() => config.retryDelay(0), throwsArgumentError); expect(() => config.retryDelay(6), throwsArgumentError);
      const immediate = BroadcastServerConfig(protocol: BroadcastProtocol.icecast, initialBackoff: Duration.zero); expect(immediate.retryDelay(1), Duration.zero);
    });
    test('zero retries makes exactly one request and no delay', () async {
      final client = _CountingClient(); var delays = 0;
      final adapter = BroadcastMetadataAdapter(config: const BroadcastServerConfig(protocol: BroadcastProtocol.icecast, maxRetries: 0), fingerprintStream: const Stream<IdentifiedTrack>.empty(), httpClient: client, sleeper: (_) async { delays++; });
      final result = await adapter.sendMetadata(track); expect(client.calls, 1); expect(result.attemptCount, 1); expect(delays, 0); await adapter.dispose();
    });
    test('configured maximum makes six requests with capped delays', () async {
      final client = _CountingClient(); final delays = <Duration>[];
      final adapter = BroadcastMetadataAdapter(config: const BroadcastServerConfig(protocol: BroadcastProtocol.icecast, maxRetries: 5, initialBackoff: Duration(seconds: 10)), fingerprintStream: const Stream<IdentifiedTrack>.empty(), httpClient: client, sleeper: (delay) async { delays.add(delay); });
      final result = await adapter.sendMetadata(track); expect(client.calls, 6); expect(result.attemptCount, 6); expect(delays.map((d) => d.inSeconds).toList(), [10, 20, 30, 30, 30]); await adapter.dispose();
    });
    test('default overlay writes through injected non-real-time boundary', () async {
      final writes = <String>[]; final client = _CountingClient();
      final adapter = BroadcastMetadataAdapter(config: const BroadcastServerConfig(protocol: BroadcastProtocol.obsHttpOverlay), fingerprintStream: const Stream<IdentifiedTrack>.empty(), httpClient: client, overlayWriter: (path, content) async { writes.add('$path|$content'); });
      expect((await adapter.sendMetadata(track)).succeeded, isTrue); expect(writes, ['live_current_track.txt|ARTIST — TITLE']); expect(client.calls, 0); await adapter.dispose();
    });
    test('invalid config builder rejects without exposing rejected host', () {
      const config = BroadcastServerConfig(protocol: BroadcastProtocol.icecast, host: 'secret-user:secret-password@host.test');
      expect(() => config.buildMetadataUri('Title'), throwsA(isA<ArgumentError>().having((e) => e.toString(), 'safe message', isNot(contains('secret-password')))));
    });
  });
}
