import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/services/fingerprint_tracklist_bridge.dart';
import '../lib/services/live_session_tracklist_controller.dart';
import '../lib/services/session_tracklist.dart';
import '../lib/services/session_tracklist_persister.dart';
import '../lib/services/session_tracklist_store.dart';

void main() {
  late Directory directory;
  setUp(() async => directory = await Directory.systemTemp.createTemp('lmm_controller_'));
  tearDown(() async => directory.delete(recursive: true));

  test('accepted match and correction are persisted when the session closes', () async {
    final tracklist = SessionTracklist();
    final store = SessionTracklistStore(file: File('${directory.path}/session.json'));
    final controller = LiveSessionTracklistController(
      sessionId: 'set-1', sourceId: 'master', tracklist: tracklist,
      bridge: FingerprintTracklistBridge(tracklist: tracklist),
      persister: SessionTracklistPersister(store: store, debounce: const Duration(days: 1)),
    );
    expect(controller.acceptFingerprint(cueTime: const Duration(seconds: 4), match: const FingerprintMatch(artist: 'Artist', title: 'Title', confidence: .9), recognizedAt: DateTime.utc(2026)), isTrue);
    controller.correct(index: 0, artist: 'Correct artist', title: 'Correct title', correctedAt: DateTime.utc(2026, 1, 2));
    await controller.close();
    final restored = await store.load();
    expect(restored.single.title, 'Correct title');
  });

  test('suppressed duplicate does not create a new entry', () async {
    final tracklist = SessionTracklist();
    final store = SessionTracklistStore(file: File('${directory.path}/session.json'));
    final controller = LiveSessionTracklistController(sessionId: 'set-1', sourceId: 'master', tracklist: tracklist, bridge: FingerprintTracklistBridge(tracklist: tracklist), persister: SessionTracklistPersister(store: store));
    final match = const FingerprintMatch(artist: 'Artist', title: 'Title', confidence: .9);
    expect(controller.acceptFingerprint(cueTime: Duration.zero, match: match, recognizedAt: DateTime.utc(2026)), isTrue);
    expect(controller.acceptFingerprint(cueTime: const Duration(seconds: 20), match: match, recognizedAt: DateTime.utc(2026)), isFalse);
    expect(controller.entries, hasLength(1));
    await controller.close();
  });
}
