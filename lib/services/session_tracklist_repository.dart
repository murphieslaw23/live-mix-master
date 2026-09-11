import 'reliability_models.dart';

abstract interface class SessionTracklistRepository {
  Stream<ServiceStatus> get onStatus;

  Future<List<TracklistEntry>> load();

  Future<void> save(Iterable<TracklistEntry> entries);

  Future<void> dispose();
}
