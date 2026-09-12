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
    required this.mixerEnabled,
    required this.fader,
    required this.muted,
    required this.solo,
    required this.channelPeak,
    required this.masterPeakLeft,
    required this.masterPeakRight,
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
  final bool mixerEnabled;
  final double fader;
  final bool muted;
  final bool solo;
  final double channelPeak;
  final double masterPeakLeft;
  final double masterPeakRight;
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
    final channelMeter = mixer.channelMeter;
    final channelPeak = channelMeter == null
        ? 0.0
        : math.max(channelMeter.peakLeft, channelMeter.peakRight);
    final masterPeak = math.max(mixer.masterPeakLeft, mixer.masterPeakRight);

    return WebReferenceLiveState(
      captureActive: captureActive,
      sourceId: source?.id,
      sourceLabel: source?.label.trim().isNotEmpty == true
          ? source!.label.trim()
          : 'NO ACTIVE SOURCE',
      recordingActive:
          recording.status == BrowserRecordingStatus.recording,
      mixerEnabled: mixer.enabled,
      fader: mixer.enabled ? mixer.fader.clamp(0.0, 1.0).toDouble() : 0,
      muted: mixer.muted,
      solo: mixer.solo,
      channelPeak: channelPeak.clamp(0.0, 1.0).toDouble(),
      masterPeakLeft: mixer.masterPeakLeft.clamp(0.0, 1.0).toDouble(),
      masterPeakRight: mixer.masterPeakRight.clamp(0.0, 1.0).toDouble(),
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
