import 'dart:async';

import 'reliability_models.dart';
import 'session_tracklist_repository.dart';

class SessionTracklistPersister {
  SessionTracklistPersister({
    required this.store,
    this.debounce = const Duration(seconds: 2),
  });

  final SessionTracklistRepository store;
  final Duration debounce;
  Timer? _timer;
  List<TracklistEntry>? _pending;
  Future<void> _write = Future<void>.value();

  Stream<ServiceStatus> get onStatus => store.onStatus;

  void schedule(Iterable<TracklistEntry> entries) {
    _pending = List<TracklistEntry>.unmodifiable(entries);
    _timer?.cancel();
    _timer = Timer(debounce, flush);
  }

  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    final snapshot = _pending;
    _pending = null;
    if (snapshot == null) return _write;
    _write = _write.then((_) => store.save(snapshot));
    return _write;
  }

  Future<void> dispose() async {
    await flush();
    await store.dispose();
  }
}
