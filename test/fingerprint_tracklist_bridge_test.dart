import 'package:flutter_test/flutter_test.dart';

import '../lib/services/fingerprint_tracklist_bridge.dart';
import '../lib/services/reliability_models.dart';
import '../lib/services/session_tracklist.dart';

void main() {
  FingerprintMatch match({double confidence = .9, String artist = 'Artist', String title = 'Title'}) =>
      FingerprintMatch(artist: artist, title: title, confidence: confidence, providerId: 'provider-id');

  test('accepted match becomes an automatic tracklist entry', () async {
    final bridge = FingerprintTracklistBridge(tracklist: SessionTracklist());
    final status = bridge.onStatus.first;
    expect(bridge.accept(sessionId: 'session', sourceId: 'master', cueTime: const Duration(seconds: 3), match: match(), recognizedAt: DateTime.utc(2026)), isTrue);
    expect(bridge.tracklist.entries.single.provenance, TrackProvenance.automatic);
    expect((await status).state, ServiceOperationState.succeeded);
    await bridge.dispose();
  });

  test('below-threshold result does not alter the tracklist', () async {
    final bridge = FingerprintTracklistBridge(tracklist: SessionTracklist(), minimumConfidence: .8);
    final status = bridge.onStatus.first;
    expect(bridge.accept(sessionId: 'session', sourceId: 'master', cueTime: Duration.zero, match: match(confidence: .79), recognizedAt: DateTime.utc(2026)), isFalse);
    expect(bridge.tracklist.entries, isEmpty);
    expect((await status).failureCode, ServiceFailureCode.unavailable);
    await bridge.dispose();
  });

  test('duplicate recognized results are suppressed by the tracklist', () async {
    final bridge = FingerprintTracklistBridge(tracklist: SessionTracklist());
    expect(bridge.accept(sessionId: 'session', sourceId: 'master', cueTime: Duration.zero, match: match(), recognizedAt: DateTime.utc(2026)), isTrue);
    expect(bridge.accept(sessionId: 'session', sourceId: 'master', cueTime: const Duration(seconds: 20), match: match(), recognizedAt: DateTime.utc(2026)), isFalse);
    expect(bridge.tracklist.entries, hasLength(1));
    await bridge.dispose();
  });
}
