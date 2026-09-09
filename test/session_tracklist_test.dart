import 'package:flutter_test/flutter_test.dart';

import '../lib/services/reliability_models.dart';
import '../lib/services/session_tracklist.dart';

TracklistEntry entry({Duration cue = const Duration(seconds: 10), String artist = 'Artist', String title = 'Title'}) => TracklistEntry(
      sessionId: 'session', sourceId: 'master', cueTime: cue, artist: artist, title: title,
      confidence: .9, provenance: TrackProvenance.automatic, createdAt: DateTime.utc(2026),
    );

void main() {
  test('suppresses duplicate automatic matches inside its debounce window', () {
    final list = SessionTracklist();
    expect(list.addAutomatic(entry()), isTrue);
    expect(list.addAutomatic(entry(cue: const Duration(seconds: 25), artist: ' artist ', title: 'TITLE')), isFalse);
    expect(list.entries, hasLength(1));
  });

  test('manual correction cannot be overwritten by a later automatic result for its cue', () {
    final list = SessionTracklist();
    list.addAutomatic(entry());
    final corrected = list.correct(index: 0, artist: 'Correct artist', title: 'Correct title', correctedAt: DateTime.utc(2026, 1, 2));
    expect(corrected.provenance, TrackProvenance.manual);
    expect(list.addAutomatic(entry(artist: 'Old artist', title: 'Old title')), isFalse);
    expect(list.entries.single.artist, 'Correct artist');
    expect(list.entries.single.provenance, TrackProvenance.manual);
  });
}
