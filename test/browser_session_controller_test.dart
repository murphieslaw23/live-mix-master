import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../lib/services/reliability_models.dart';
import '../lib/services/session_tracklist_repository.dart';
import '../lib/services/web/browser_session_controller.dart';

TracklistEntry recoveredEntry() => TracklistEntry(
      sessionId: 'stored-session',
      sourceId: 'browser-master',
      cueTime: const Duration(minutes: 12, seconds: 34),
      artist: 'Recovered Artist',
      title: 'Recovered Title',
      confidence: 1,
      provenance: TrackProvenance.manual,
      createdAt: DateTime.utc(2026, 9, 11, 8),
      updatedAt: DateTime.utc(2026, 9, 11, 8, 30),
    );

void main() {
  test('initialize recovers persisted entries and keeps stored session identity', () async {
    final repository = _FakeSessionTracklistRepository(
      initialEntries: <TracklistEntry>[recoveredEntry()],
    );
    final downloads = _FakeDownloadGateway();
    final controller = BrowserSessionController(
      repository: repository,
      downloadGateway: downloads,
      createSessionId: () => 'generated-session',
      clock: () => DateTime.utc(2026, 9, 11, 10),
    );

    await controller.initialize();

    expect(controller.sessionId, 'stored-session');
    expect(controller.entries, hasLength(1));
    expect(controller.entries.single.provenance, TrackProvenance.manual);
    expect(controller.entries.single.title, 'Recovered Title');

    await controller.dispose();
  });

  test('empty storage creates one stable local session identity', () async {
    final repository = _FakeSessionTracklistRepository();
    final controller = BrowserSessionController(
      repository: repository,
      downloadGateway: _FakeDownloadGateway(),
      createSessionId: () => 'generated-session',
      clock: () => DateTime.utc(2026, 9, 11, 10),
    );

    await controller.initialize();

    expect(controller.sessionId, 'generated-session');
    expect(controller.entries, isEmpty);

    await controller.dispose();
  });

  test('manual correction is persisted before the operation completes', () async {
    final repository = _FakeSessionTracklistRepository(
      initialEntries: <TracklistEntry>[recoveredEntry()],
    );
    final controller = BrowserSessionController(
      repository: repository,
      downloadGateway: _FakeDownloadGateway(),
      createSessionId: () => 'generated-session',
      clock: () => DateTime.utc(2026, 9, 11, 10),
    );
    await controller.initialize();

    final corrected = await controller.correct(
      index: 0,
      artist: 'Corrected Artist',
      title: 'Corrected Title',
    );

    expect(corrected.provenance, TrackProvenance.manual);
    expect(corrected.artist, 'Corrected Artist');
    expect(corrected.title, 'Corrected Title');
    expect(repository.savedSnapshots, hasLength(1));
    expect(repository.savedSnapshots.single.single.title, 'Corrected Title');

    await controller.dispose();
  });

  test('exports recovered session through existing JSON CSV and M3U formats', () async {
    final repository = _FakeSessionTracklistRepository(
      initialEntries: <TracklistEntry>[recoveredEntry()],
    );
    final downloads = _FakeDownloadGateway();
    final controller = BrowserSessionController(
      repository: repository,
      downloadGateway: downloads,
      createSessionId: () => 'generated-session',
      clock: () => DateTime.utc(2026, 9, 11, 10),
    );
    await controller.initialize();

    await controller.exportJson();
    await controller.exportCsv();
    await controller.exportM3u();

    expect(downloads.requests, hasLength(3));
    expect(downloads.requests[0].fileName, endsWith('.json'));
    expect(downloads.requests[0].mimeType, 'application/json');
    expect(downloads.requests[0].contents, contains('Recovered Title'));
    expect(downloads.requests[1].fileName, endsWith('.csv'));
    expect(downloads.requests[1].mimeType, 'text/csv;charset=utf-8');
    expect(downloads.requests[1].contents, contains('Recovered Artist'));
    expect(downloads.requests[2].fileName, endsWith('.m3u'));
    expect(downloads.requests[2].mimeType, 'audio/x-mpegurl');
    expect(downloads.requests[2].contents, contains('#EXTM3U'));

    await controller.dispose();
  });
}

class _FakeSessionTracklistRepository implements SessionTracklistRepository {
  _FakeSessionTracklistRepository({
    List<TracklistEntry> initialEntries = const <TracklistEntry>[],
  }) : _entries = List<TracklistEntry>.of(initialEntries);

  final StreamController<ServiceStatus> _statuses =
      StreamController<ServiceStatus>.broadcast();
  List<TracklistEntry> _entries;
  final List<List<TracklistEntry>> savedSnapshots = <List<TracklistEntry>>[];

  @override
  Stream<ServiceStatus> get onStatus => _statuses.stream;

  @override
  Future<List<TracklistEntry>> load() async =>
      List<TracklistEntry>.unmodifiable(_entries);

  @override
  Future<void> save(Iterable<TracklistEntry> entries) async {
    final snapshot = List<TracklistEntry>.unmodifiable(entries);
    savedSnapshots.add(snapshot);
    _entries = List<TracklistEntry>.of(snapshot);
  }

  @override
  Future<void> dispose() => _statuses.close();
}

class _FakeDownloadGateway implements BrowserTracklistDownloadGateway {
  final List<_DownloadRequest> requests = <_DownloadRequest>[];

  @override
  Future<void> download({
    required String fileName,
    required String mimeType,
    required String contents,
  }) async {
    requests.add(
      _DownloadRequest(
        fileName: fileName,
        mimeType: mimeType,
        contents: contents,
      ),
    );
  }
}

class _DownloadRequest {
  const _DownloadRequest({
    required this.fileName,
    required this.mimeType,
    required this.contents,
  });

  final String fileName;
  final String mimeType;
  final String contents;
}
