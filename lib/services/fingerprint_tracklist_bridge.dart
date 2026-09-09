import 'dart:async';

import 'reliability_models.dart';
import 'session_tracklist.dart';

class FingerprintMatch {
  const FingerprintMatch({
    required this.artist,
    required this.title,
    required this.confidence,
    this.providerId,
  });

  final String artist;
  final String title;
  final double confidence;
  final String? providerId;
}

class FingerprintTracklistBridge {
  FingerprintTracklistBridge({
    required this.tracklist,
    this.minimumConfidence = 0.7,
  }) : assert(minimumConfidence >= 0 && minimumConfidence <= 1);

  final SessionTracklist tracklist;
  final double minimumConfidence;
  final StreamController<ServiceStatus> _statuses = StreamController<ServiceStatus>.broadcast();

  Stream<ServiceStatus> get onStatus => _statuses.stream;

  bool accept({
    required String sessionId,
    required String sourceId,
    required Duration cueTime,
    required FingerprintMatch match,
    required DateTime recognizedAt,
  }) {
    if (match.confidence < minimumConfidence) {
      _emit(ServiceStatus.failed(
        failureCode: ServiceFailureCode.unavailable,
        message: 'Fingerprint confidence is below the acceptance threshold',
      ));
      return false;
    }
    final accepted = tracklist.addAutomatic(TracklistEntry(
      sessionId: sessionId,
      sourceId: sourceId,
      cueTime: cueTime,
      artist: match.artist,
      title: match.title,
      confidence: match.confidence,
      providerId: match.providerId,
      provenance: TrackProvenance.automatic,
      createdAt: recognizedAt,
    ));
    _emit(const ServiceStatus.succeeded());
    return accepted;
  }

  Future<void> dispose() => _statuses.close();

  void _emit(ServiceStatus status) {
    if (!_statuses.isClosed) _statuses.add(status);
  }
}
