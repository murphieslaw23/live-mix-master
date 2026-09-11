import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

enum FingerprintProxyOutcome {
  matched,
  noMatch,
  failed,
}

enum FingerprintProxyFailureCode {
  invalidRequest,
  invalidConfiguration,
  timeout,
  cancelled,
  offline,
  unauthorized,
  rateLimited,
  malformedResponse,
  unavailable,
  unknown,
}

class FingerprintProxyTrack {
  final String artist;
  final String title;
  final String? release;
  final String providerId;
  final double confidence;

  const FingerprintProxyTrack({
    required this.artist,
    required this.title,
    required this.release,
    required this.providerId,
    required this.confidence,
  });
}

class FingerprintProxyResult {
  final FingerprintProxyOutcome outcome;
  final FingerprintProxyTrack? track;
  final FingerprintProxyFailureCode? failureCode;
  final String? message;

  const FingerprintProxyResult._({
    required this.outcome,
    this.track,
    this.failureCode,
    this.message,
  });

  const FingerprintProxyResult.matched(FingerprintProxyTrack track)
      : this._(
          outcome: FingerprintProxyOutcome.matched,
          track: track,
        );

  const FingerprintProxyResult.noMatch()
      : this._(outcome: FingerprintProxyOutcome.noMatch);

  const FingerprintProxyResult.failed({
    required FingerprintProxyFailureCode failureCode,
    required String message,
  }) : this._(
          outcome: FingerprintProxyOutcome.failed,
          failureCode: failureCode,
          message: message,
        );
}

class FingerprintProxyClient {
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Uri endpoint;
  final Duration requestTimeout;

  FingerprintProxyClient({
    http.Client? httpClient,
    Uri? endpoint,
    this.requestTimeout = const Duration(seconds: 8),
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        endpoint = endpoint ?? Uri.base.resolve('/api/fingerprint-lookup');

  Future<FingerprintProxyResult> lookup({
    required String fingerprint,
    required int durationSeconds,
    double minimumConfidence = 0.65,
  }) async {
    if (
        fingerprint.isEmpty ||
        durationSeconds < 1 ||
        durationSeconds > 120 ||
        minimumConfidence < 0 ||
        minimumConfidence > 1) {
      return const FingerprintProxyResult.failed(
        failureCode: FingerprintProxyFailureCode.invalidRequest,
        message: 'Fingerprint lookup request is invalid',
      );
    }

    http.Response response;
    try {
      response = await _httpClient
          .post(
            endpoint,
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({
              'duration': durationSeconds,
              'fingerprint': fingerprint,
              'minimumConfidence': minimumConfidence,
            }),
          )
          .timeout(requestTimeout);
    } on TimeoutException {
      return const FingerprintProxyResult.failed(
        failureCode: FingerprintProxyFailureCode.timeout,
        message: 'Fingerprint proxy request timed out',
      );
    } on http.ClientException {
      return const FingerprintProxyResult.failed(
        failureCode: FingerprintProxyFailureCode.offline,
        message: 'Fingerprint proxy is unreachable',
      );
    } catch (_) {
      return const FingerprintProxyResult.failed(
        failureCode: FingerprintProxyFailureCode.unknown,
        message: 'Fingerprint proxy request failed',
      );
    }

    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      return const FingerprintProxyResult.failed(
        failureCode: FingerprintProxyFailureCode.malformedResponse,
        message: 'Fingerprint proxy returned malformed data',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      return const FingerprintProxyResult.failed(
        failureCode: FingerprintProxyFailureCode.malformedResponse,
        message: 'Fingerprint proxy returned malformed data',
      );
    }

    if (response.statusCode == 200 && decoded['ok'] == true) {
      final track = decoded['track'];
      if (track == null) {
        return const FingerprintProxyResult.noMatch();
      }
      if (track is! Map<String, dynamic>) {
        return const FingerprintProxyResult.failed(
          failureCode: FingerprintProxyFailureCode.malformedResponse,
          message: 'Fingerprint proxy returned malformed data',
        );
      }

      final artist = track['artist'];
      final title = track['title'];
      final release = track['release'];
      final providerId = track['providerId'];
      final confidence = track['confidence'];
      if (
          artist is! String ||
          title is! String ||
          (release != null && release is! String) ||
          providerId is! String ||
          confidence is! num) {
        return const FingerprintProxyResult.failed(
          failureCode: FingerprintProxyFailureCode.malformedResponse,
          message: 'Fingerprint proxy returned malformed data',
        );
      }

      return FingerprintProxyResult.matched(
        FingerprintProxyTrack(
          artist: artist,
          title: title,
          release: release as String?,
          providerId: providerId,
          confidence: confidence.toDouble(),
        ),
      );
    }

    if (decoded['ok'] == false) {
      return FingerprintProxyResult.failed(
        failureCode: _failureCode(decoded['failureCode']),
        message: decoded['message'] is String
            ? decoded['message'] as String
            : 'Fingerprint proxy request failed',
      );
    }

    return const FingerprintProxyResult.failed(
      failureCode: FingerprintProxyFailureCode.malformedResponse,
      message: 'Fingerprint proxy returned malformed data',
    );
  }

  void close() {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }
}

FingerprintProxyFailureCode _failureCode(Object? value) {
  if (value is String) {
    for (final code in FingerprintProxyFailureCode.values) {
      if (code.name == value) {
        return code;
      }
    }
  }
  return FingerprintProxyFailureCode.unknown;
}
