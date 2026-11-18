import 'dart:async';

import 'reliability_models.dart';
import 'session_tracklist_repository.dart';

class SessionTracklistPersister {
  SessionTracklistPersister({
    required this.store,
    this.debounce = const Duration(seconds: 2),
  }) {
    if (debounce.isNegative) {
      throw ArgumentError.value(debounce, 'debounce', 'Must not be negative');
    }
  }

  final SessionTracklistRepository store;
  final Duration debounce;
  Timer? _timer;
  List<TracklistEntry>? _pending;
  int _revision = 0;
  bool _accepting = true;
  Future<void> _queue = Future<void>.value();
  Future<void> _lastWrite = Future<void>.value();
  Future<void>? _disposeFuture;

  Stream<ServiceStatus> get onStatus => store.onStatus;

  void schedule(Iterable<TracklistEntry> entries) {
    if (!_accepting) throw StateError('Persister is closing or closed');
    _revision++;
    _pending = List<TracklistEntry>.unmodifiable(entries);
    _timer?.cancel();
    _timer = Timer(debounce, () {
      // Repository failures remain observable through onStatus.
      unawaited(flush().then<void>((_) {}, onError: (Object error, StackTrace stack) {}));
    });
  }

  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    final snapshot = _pending;
    final revision = _revision;
    _pending = null;
    if (snapshot == null) return _lastWrite;
    final operation = _queue.then((_) async {
      try {
        await store.save(snapshot);
      } catch (_) {
        if (_revision == revision && _pending == null) {
          _pending = snapshot;
        }
        rethrow;
      }
    });
    _lastWrite = operation;
    // Keep serialization alive while callers still receive the write failure.
    _queue = operation.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return operation;
  }

  Future<void> dispose() {
    _accepting = false;
    return _disposeFuture ??= _close();
  }

  Future<void> _close() async {
    try {
      await flush();
    } finally {
      await store.dispose();
    }
  }
}
