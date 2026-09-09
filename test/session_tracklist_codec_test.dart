import 'package:flutter_test/flutter_test.dart';

import '../lib/services/reliability_models.dart';
import '../lib/services/session_tracklist_codec.dart';

void main() {
  test('round trips automatic and manually corrected entries', () {
    final entries = [
      TracklistEntry(sessionId: 'set-1', sourceId: 'master', cueTime: const Duration(seconds: 12), artist: 'Artist', title: 'Title', confidence: .82, providerId: 'id-1', provenance: TrackProvenance.automatic, createdAt: DateTime.utc(2026, 9, 9)),
      TracklistEntry(sessionId: 'set-1', sourceId: 'master', cueTime: const Duration(seconds: 34), artist: 'Correct artist', title: 'Correct title', confidence: 1, provenance: TrackProvenance.manual, createdAt: DateTime.utc(2026, 9, 9), updatedAt: DateTime.utc(2026, 9, 9, 1)),
    ];
    final restored = const SessionTracklistCodec().decode(const SessionTracklistCodec().encode(entries));
    expect(restored, hasLength(2));
    expect(restored[0].providerId, 'id-1');
    expect(restored[1].provenance, TrackProvenance.manual);
    expect(restored[1].updatedAt, DateTime.utc(2026, 9, 9, 1));
  });

  test('rejects an unsupported document', () {
    expect(() => const SessionTracklistCodec().decode('{"schemaVersion":2,"entries":[]}'), throwsFormatException);
  });
}
