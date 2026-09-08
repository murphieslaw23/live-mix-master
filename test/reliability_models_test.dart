import 'package:flutter_test/flutter_test.dart';

import '../lib/services/reliability_models.dart';

void main() {
  final createdAt = DateTime.utc(2026, 9, 8, 10);

  TracklistEntry entry({
    String artist = 'Example Artist',
    String title = 'Example Title',
    Duration cueTime = const Duration(seconds: 30),
    TrackProvenance provenance = TrackProvenance.automatic,
    String? providerId,
  }) =>
      TracklistEntry(
        sessionId: 'session-1',
        cueTime: cueTime,
        sourceId: 'master',
        artist: artist,
        title: title,
        confidence: .82,
        provenance: provenance,
        providerId: providerId,
        createdAt: createdAt,
      );

  test('recording configuration rejects invalid values before capture', () {
    const config = RecordingConfig(
      destinationPath: '',
      sampleRateHz: 0,
      channelCount: 2,
      sampleFormat: SampleFormat.pcm16,
    );
    expect(config.validationFailure, ServiceFailureCode.invalidConfiguration);
  });

  test('recording configuration exposes sample format bit depth', () {
    const config = RecordingConfig(
      destinationPath: '/tmp/set.wav',
      sampleRateHz: 48000,
      channelCount: 2,
      sampleFormat: SampleFormat.pcm24,
    );
    expect(config.validationFailure, isNull);
    expect(config.bitsPerSample, 24);
  });

  test('automatic duplicate within debounce window is suppressed', () {
    final original = entry();
    final candidate = entry(
      artist: '  example   artist ',
      title: 'EXAMPLE TITLE',
      cueTime: const Duration(seconds: 37),
    );
    expect(
      shouldSuppressAutomaticMatch(
        candidate: candidate,
        existing: [original],
        debounceWindow: const Duration(seconds: 10),
      ),
      isTrue,
    );
  });

  test('manual correction is preserved as manual provenance', () {
    final corrected = entry().applyManualCorrection(
      artist: 'Correct Artist',
      title: 'Correct Title',
      correctedAt: createdAt.add(const Duration(minutes: 1)),
    );
    expect(corrected.provenance, TrackProvenance.manual);
    expect(corrected.confidence, 1);
    expect(corrected.artist, 'Correct Artist');
  });

  test('diagnostics redact secrets', () {
    final value = redactDiagnostic(
      'Authorization: Bearer secret-token password=super-secret',
    );
    expect(value, isNot(contains('secret-token')));
    expect(value, isNot(contains('super-secret')));
    expect(value, contains('[REDACTED]'));
  });
}
