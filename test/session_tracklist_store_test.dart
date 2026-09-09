import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/services/reliability_models.dart';
import '../lib/services/session_tracklist_store.dart';

void main() {
  late Directory directory;

  setUp(() async => directory = await Directory.systemTemp.createTemp('lmm_tracklist_'));
  tearDown(() async => directory.delete(recursive: true));

  test('persists and reloads a session tracklist', () async {
    final store = SessionTracklistStore(file: File('${directory.path}/session.json'));
    final status = store.onStatus.where((item) => item.state == ServiceOperationState.succeeded).first;
    final entries = [TracklistEntry(sessionId: 'session', sourceId: 'master', cueTime: const Duration(seconds: 8), artist: 'Artist', title: 'Title', confidence: .9, provenance: TrackProvenance.automatic, createdAt: DateTime.utc(2026))];
    await store.save(entries);
    expect((await status).state, ServiceOperationState.succeeded);
    final restored = await store.load();
    expect(restored.single.title, 'Title');
    expect(await File('${directory.path}/session.json.tmp').exists(), isFalse);
    await store.dispose();
  });

  test('invalid stored JSON emits a typed malformed status', () async {
    final file = File('${directory.path}/session.json');
    await file.writeAsString('{invalid');
    final store = SessionTracklistStore(file: file);
    final status = store.onStatus.where((item) => item.state == ServiceOperationState.failed).first;
    await expectLater(store.load(), throwsFormatException);
    expect((await status).failureCode, ServiceFailureCode.malformedResponse);
    await store.dispose();
  });
}
