import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/services/reliability_models.dart';
import '../lib/services/session_tracklist_persister.dart';
import '../lib/services/session_tracklist_store.dart';

TracklistEntry entry(String title) => TracklistEntry(sessionId: 'session', sourceId: 'master', cueTime: Duration.zero, artist: 'Artist', title: title, confidence: .9, provenance: TrackProvenance.automatic, createdAt: DateTime.utc(2026));

void main() {
  late Directory directory;
  setUp(() async => directory = await Directory.systemTemp.createTemp('lmm_persister_'));
  tearDown(() async => directory.delete(recursive: true));

  test('coalesces rapid updates and writes the latest snapshot', () async {
    final store = SessionTracklistStore(file: File('${directory.path}/session.json'));
    final persister = SessionTracklistPersister(store: store, debounce: const Duration(milliseconds: 10));
    persister.schedule([entry('First')]);
    persister.schedule([entry('Latest')]);

    // `flush` is the persister's completion barrier. If the debounce timer has
    // already fired it awaits the in-flight write; if not, it cancels the timer
    // and persists the coalesced latest snapshot immediately. Do not infer
    // asynchronous file completion from an arbitrary wall-clock delay.
    await persister.flush();

    expect((await store.load()).single.title, 'Latest');
    await persister.dispose();
  });

  test('flush writes without waiting for the debounce timer', () async {
    final store = SessionTracklistStore(file: File('${directory.path}/session.json'));
    final persister = SessionTracklistPersister(store: store, debounce: const Duration(days: 1));
    persister.schedule([entry('Immediate')]);
    await persister.flush();
    expect((await store.load()).single.title, 'Immediate');
    await persister.dispose();
  });
}
