import 'dart:math' as math;

import '../audio/web/browser_capture_controller.dart';
import '../audio/web/browser_mixer_controller.dart';
import '../audio/web/browser_recording_controller.dart';
import '../services/web/browser_fingerprint_lookup_controller.dart';

/// Truthful presentation snapshot for the reference-first Web surface.
///
/// Only fields backed by verified W5 browser controller state are populated.
/// Broadcast state, stream bitrate, LUFS and dBTP remain unavailable until a
/// separately verified Web source exists for those measurements.
class WebReferenceLiveState {
  const WebReferenceLiveState({
    required this.captureActive,
    required this.sourceId,
    required this.sourceLabel,
    required this.recordingActive,
    required this.masterPeakLevel,
    required this.limiterActive,
    required this.currentArtist,
    required this.currentTrackTitle,
    required this.matchConfidence,
    required this.streamBitrateKbps,
    required this.loudnessLufs,
    required this.truePeakDbtp,
    required this.broadcastConfigured,
    required this.isStreaming,
  });

  final bool captureActive;
  final String? sourceId;
  final String sourceLabel;
  final bool recordingActive;
  final double masterPeakLevel;
  final bool limiterActive;
  final String currentArtist;
  final String currentTrackTitle;
  final double? matchConfidence;
  final double? streamBitrateKbps;
  final double? loudnessLufs;
  final double? truePeakDbtp;
  final bool broadcastConfigured;
  final bool isStreaming;

  factory WebReferenceLiveState.fromBrowserStates({
    required BrowserCaptureState capture,
    required BrowserMixerState mixer,
    required BrowserRecordingState recording,
    required BrowserFingerprintLookupState fingerprint,
  }) {
    final captureActive = capture.status == BrowserCaptureStatus.active;
    final source = captureActive ? capture.source : null;
    final matched =
        fingerprint.status == BrowserFingerprintLookupStatus.matched
            ? fingerprint.track
            : null;
    final masterPeak = math.max(mixer.masterPeakLeft, mixer.masterPeakRight);

    return WebReferenceLiveState(
      captureActive: captureActive,
      sourceId: source?.id,
      sourceLabel: source?.label.trim().isNotEmpty == true
          ? source!.label.trim()
          : 'NO ACTIVE SOURCE',
      recordingActive:
          recording.status == BrowserRecordingStatus.recording,
      masterPeakLevel: masterPeak.clamp(0.0, 1.0).toDouble(),
      limiterActive: mixer.limiterActive,
      currentArtist: matched?.artist.trim().isNotEmpty == true
          ? matched!.artist.trim()
          : 'UNKNOWN ARTIST',
      currentTrackTitle: matched?.title.trim().isNotEmpty == true
          ? matched!.title.trim()
          : 'AWAITING TRACK DETECTION...',
      matchConfidence: matched?.confidence,
      streamBitrateKbps: null,
      loudnessLufs: null,
      truePeakDbtp: null,
      broadcastConfigured: false,
      isStreaming: false,
    );
  }
}
