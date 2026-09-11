import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../lib/services/reliability_models.dart';
import '../lib/services/session_tracklist_persister.dart';
import '../lib/services/session_tracklist_repository.dart';

TracklistEntry entry(String title) => TracklistEntry(
      sessionId: 'session',
      sourceId: 'master',
      cueTime: Duration.zero,
      artist: 'Artist',
      title: title,
      confidence: .9,
      provenance: TrackProvenance.automatic,
      createdAt: DateTime.utc(2026),
    );

void main() {
  test('coalesces rapid updates and writes only the latest snapshot', () async {
    final repository = _FakeSessionTracklistRepository();
    final persister = SessionTracklistPersister(
      store: repository,
      debounce: const Duration(milliseconds: 10),
    );

    persister.schedule(<TracklistEntry>[entry('First')]);
    persister.schedule(<TracklistEntry>[entry('Latest')]);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await persister.flush();

    expect(repository.savedSnapshots, hasLength(1));
    expect(repository.savedSnapshots.single.single.title, 'Latest');

    await persister.dispose();
    expect(repository.disposed, isTrue);
  });

  test('flush writes immediately without waiting for debounce', () async {
    final repository = _FakeSessionTracklistRepository();
    final persister = SessionTracklistPersister(
      store: repository,
      debounce: const Duration(days: 1),
    );

    persister.schedule(<TracklistEntry>[entry('Immediate')]);
    await persister.flush();

    expect(repository.savedSnapshots, hasLength(1));
    expect(repository.savedSnapshots.single.single.title, 'Immediate');

    await persister.dispose();
  });

  test('exposes repository service status unchanged', () async {
    final repository = _FakeSessionTracklistRepository();
    final persister = SessionTracklistPersister(store: repository);
    final statuses = <ServiceStatus>[];
    final subscription = persister.onStatus.listen(statuses.add);

    repository.emit(const ServiceStatus.running());
    await Future<void>.delayed(Duration.zero);

    expect(statuses.single, const ServiceStatus.running());

    await subscription.cancel();
    await persister.dispose();
  });
}

class _FakeSessionTracklistRepository implements SessionTracklistRepository {
  final StreamController<ServiceStatus> _statuses =
      StreamController<ServiceStatus>.broadcast();
  final List<List<TracklistEntry>> savedSnapshots = <List<TracklistEntry>>[];
  bool disposed = false;

  @override
  Stream<ServiceStatus> get onStatus => _statuses.stream;

  @override
  Future<List<TracklistEntry>> load() async => const <TracklistEntry>[];

  @override
  Future<void> save(Iterable<TracklistEntry> entries) async {
    savedSnapshots.add(List<TracklistEntry>.unmodifiable(entries));
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _statuses.close();
  }

  void emit(ServiceStatus status) {
    _statuses.add(status);
  }
}
