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

  test('failed explicit write can retry the retained snapshot', () async {
    final repository = _FakeSessionTracklistRepository()..failuresRemaining = 1;
    final persister = SessionTracklistPersister(store: repository, debounce: const Duration(days: 1));
    persister.schedule([entry('Retained')]);
    await expectLater(persister.flush(), throwsStateError);
    await persister.flush();
    expect(repository.savedSnapshots.single.single.title, 'Retained');
    expect(repository.calls, 2);
    await persister.dispose();
  });

  test('newer snapshot is saved after a previous write fails', () async {
    final repository = _FakeSessionTracklistRepository()..failuresRemaining = 1;
    final persister = SessionTracklistPersister(store: repository, debounce: const Duration(days: 1));
    persister.schedule([entry('Old')]);
    await expectLater(persister.flush(), throwsStateError);
    persister.schedule([entry('Newest')]);
    await persister.flush();
    expect(repository.savedSnapshots.single.single.title, 'Newest');
    await persister.dispose();
  });

  test('in-flight failure does not replace a newer pending snapshot', () async {
    final gate = Completer<void>();
    final repository = _FakeSessionTracklistRepository()
      ..failuresRemaining = 1
      ..firstSaveGate = gate;
    final persister = SessionTracklistPersister(store: repository, debounce: const Duration(days: 1));
    persister.schedule([entry('Old')]);
    final failed = expectLater(persister.flush(), throwsStateError);
    await repository.firstSaveStarted.future;
    persister.schedule([entry('Newest')]);
    gate.complete();
    await failed;
    await persister.flush();
    expect(repository.savedSnapshots.single.single.title, 'Newest');
    await persister.dispose();
  });

  test('timer write failure is observable and retryable without an unhandled error', () async {
    final repository = _FakeSessionTracklistRepository()..failuresRemaining = 1;
    final persister = SessionTracklistPersister(store: repository, debounce: Duration.zero);
    final failure = persister.onStatus.where((status) => status.state == ServiceOperationState.failed).first;
    persister.schedule([entry('Timer snapshot')]);
    expect((await failure).failureCode, ServiceFailureCode.writeFailed);
    await Future<void>.delayed(Duration.zero);
    await persister.flush();
    expect(repository.savedSnapshots.single.single.title, 'Timer snapshot');
    await persister.dispose();
  });

  test('dispose releases repository even when final flush fails', () async {
    final repository = _FakeSessionTracklistRepository()..failuresRemaining = 1;
    final persister = SessionTracklistPersister(store: repository, debounce: const Duration(days: 1));
    persister.schedule([entry('Final snapshot')]);
    await expectLater(persister.dispose(), throwsStateError);
    expect(repository.disposed, isTrue);
    expect(() => persister.schedule([entry('Too late')]), throwsStateError);
  });

  test('negative debounce is rejected', () async {
    final repository = _FakeSessionTracklistRepository();
    expect(() => SessionTracklistPersister(store: repository, debounce: const Duration(milliseconds: -1)), throwsArgumentError);
    await repository.dispose();
  });
}

class _FakeSessionTracklistRepository implements SessionTracklistRepository {
  final StreamController<ServiceStatus> _statuses = StreamController<ServiceStatus>.broadcast();
  final List<List<TracklistEntry>> savedSnapshots = <List<TracklistEntry>>[];
  final Completer<void> firstSaveStarted = Completer<void>();
  Completer<void>? firstSaveGate;
  int failuresRemaining = 0;
  int calls = 0;
  bool disposed = false;

  @override
  Stream<ServiceStatus> get onStatus => _statuses.stream;

  @override
  Future<List<TracklistEntry>> load() async => const <TracklistEntry>[];

  @override
  Future<void> save(Iterable<TracklistEntry> entries) async {
    calls++;
    if (calls == 1) {
      firstSaveStarted.complete();
      if (firstSaveGate != null) await firstSaveGate!.future;
    }
    if (failuresRemaining > 0) {
      failuresRemaining--;
      emit(const ServiceStatus.failed(failureCode: ServiceFailureCode.writeFailed, message: 'Simulated persistence failure'));
      throw StateError('Simulated persistence failure');
    }
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
