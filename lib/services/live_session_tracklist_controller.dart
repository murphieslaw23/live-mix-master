import 'fingerprint_tracklist_bridge.dart';
import 'reliability_models.dart';
import 'session_tracklist.dart';
import 'session_tracklist_persister.dart';

class LiveSessionTracklistController {
  LiveSessionTracklistController({
    required this.sessionId,
    required this.sourceId,
    required this.tracklist,
    required this.bridge,
    required this.persister,
  });

  final String sessionId;
  final String sourceId;
  final SessionTracklist tracklist;
  final FingerprintTracklistBridge bridge;
  final SessionTracklistPersister persister;

  List<TracklistEntry> get entries => tracklist.entries;

  bool acceptFingerprint({
    required Duration cueTime,
    required FingerprintMatch match,
    required DateTime recognizedAt,
  }) {
    final accepted = bridge.accept(
      sessionId: sessionId,
      sourceId: sourceId,
      cueTime: cueTime,
      match: match,
      recognizedAt: recognizedAt,
    );
    if (accepted) persister.schedule(entries);
    return accepted;
  }

  TracklistEntry correct({
    required int index,
    required String artist,
    required String title,
    required DateTime correctedAt,
  }) {
    final corrected = tracklist.correct(
      index: index,
      artist: artist,
      title: title,
      correctedAt: correctedAt,
    );
    persister.schedule(entries);
    return corrected;
  }

  Future<void> close() => persister.dispose();
}
