import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:live_mix_master/services/web/fingerprint_proxy_client.dart';

void main() {
  group('FingerprintProxyClient', () {
    test('sends only prepared lookup data to the same-origin proxy', () async {
      late http.Request captured;
      final httpClient = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'ok': true,
            'track': {
              'artist': 'System Corrupt',
              'title': 'Signal Ritual',
              'release': 'Test Release',
              'providerId': 'acoustid-1',
              'confidence': 0.93,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = FingerprintProxyClient(
        httpClient: httpClient,
        endpoint: Uri.parse('https://livemixmaster.test/api/fingerprint-lookup'),
      );

      final result = await client.lookup(
        fingerprint: 'prepared-fingerprint',
        durationSeconds: 10,
        minimumConfidence: 0.65,
      );

      expect(captured.method, 'POST');
      expect(captured.url.path, '/api/fingerprint-lookup');
      expect(captured.headers['content-type'], contains('application/json'));
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body, {
        'duration': 10,
        'fingerprint': 'prepared-fingerprint',
        'minimumConfidence': 0.65,
      });
      expect(captured.body, isNot(contains('acoustIdApiKey')));
      expect(captured.body, isNot(contains('ACOUSTID_API_KEY')));
      expect(captured.body, isNot(contains('"client"')));

      expect(result.outcome, FingerprintProxyOutcome.matched);
      expect(result.track?.artist, 'System Corrupt');
      expect(result.track?.title, 'Signal Ritual');
      expect(result.track?.providerId, 'acoustid-1');
      expect(result.track?.confidence, 0.93);
    });

    test('maps a successful no-match response without inventing a failure', () async {
      final client = FingerprintProxyClient(
        httpClient: MockClient((_) async => http.Response(
          jsonEncode({'ok': true, 'track': null}),
          200,
        )),
        endpoint: Uri.parse('https://livemixmaster.test/api/fingerprint-lookup'),
      );

      final result = await client.lookup(
        fingerprint: 'prepared-fingerprint',
        durationSeconds: 10,
      );

      expect(result.outcome, FingerprintProxyOutcome.noMatch);
      expect(result.track, isNull);
      expect(result.failureCode, isNull);
    });

    test('preserves safe typed proxy failures for operator state', () async {
      final client = FingerprintProxyClient(
        httpClient: MockClient((_) async => http.Response(
          jsonEncode({
            'ok': false,
            'failureCode': 'rateLimited',
            'message': 'Fingerprint provider rate limit exceeded',
          }),
          503,
        )),
        endpoint: Uri.parse('https://livemixmaster.test/api/fingerprint-lookup'),
      );

      final result = await client.lookup(
        fingerprint: 'prepared-fingerprint',
        durationSeconds: 10,
      );

      expect(result.outcome, FingerprintProxyOutcome.failed);
      expect(result.failureCode, FingerprintProxyFailureCode.rateLimited);
      expect(result.message, 'Fingerprint provider rate limit exceeded');
      expect(result.track, isNull);
    });

    test('malformed proxy data fails closed with a local safe diagnostic', () async {
      final client = FingerprintProxyClient(
        httpClient: MockClient((_) async => http.Response('{not-json', 200)),
        endpoint: Uri.parse('https://livemixmaster.test/api/fingerprint-lookup'),
      );

      final result = await client.lookup(
        fingerprint: 'prepared-fingerprint',
        durationSeconds: 10,
      );

      expect(result.outcome, FingerprintProxyOutcome.failed);
      expect(result.failureCode, FingerprintProxyFailureCode.malformedResponse);
      expect(result.message, 'Fingerprint proxy returned malformed data');
    });
  });
}
