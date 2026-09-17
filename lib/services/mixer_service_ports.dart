import 'fingerprint_service.dart' show IdentifiedTrack;
import 'lossless_recording_writer.dart' show RecordingStats;

/// Stable recording surface consumed by mixer widgets.
abstract interface class MixerRecordingPort {
  Stream<RecordingStats> get onStatsUpdated;
  Future<String> startRecording();
  Future<RecordingStats> stopRecording();
}

/// Stable fingerprint surface consumed by mixer widgets.
abstract interface class MixerFingerprintPort {
  Stream<IdentifiedTrack> get onTrackIdentified;
  Stream<bool> get onAnalyzingStatusChanged;
}
