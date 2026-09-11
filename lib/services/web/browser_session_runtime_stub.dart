import 'dart:async';

import '../reliability_models.dart';
import '../session_tracklist_repository.dart';
import 'browser_session_controller.dart';

BrowserSessionController createBrowserSessionController() {
  return BrowserSessionController(
    repository: _MemoryBrowserSessionRepository(),
    downloadGateway: const _UnsupportedDownloadGateway(),
  );
}

class _MemoryBrowserSessionRepository implements SessionTracklistRepository {
  final StreamController<ServiceStatus> _statuses =
      StreamController<ServiceStatus>.broadcast();
  List<TracklistEntry> _entries = const <TracklistEntry>[];

  @override
  Stream<ServiceStatus> get onStatus => _statuses.stream;

  @override
  Future<List<TracklistEntry>> load() async => List<TracklistEntry>.of(_entries);

  @override
  Future<void> save(Iterable<TracklistEntry> entries) async {
    _entries = List<TracklistEntry>.of(entries);
    if (!_statuses.isClosed) {
      _statuses.add(const ServiceStatus.succeeded());
    }
  }

  @override
  Future<void> dispose() => _statuses.close();
}

class _UnsupportedDownloadGateway implements BrowserTracklistDownloadGateway {
  const _UnsupportedDownloadGateway();

  @override
  Future<void> download({
    required String fileName,
    required String mimeType,
    required String contents,
  }) async {
    throw StateError('BROWSER DOWNLOAD UNAVAILABLE OUTSIDE WEB RUNTIME');
  }
}
