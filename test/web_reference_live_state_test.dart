import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/app/web_reference_live_state.dart';
import 'package:live_mix_master/audio/web/browser_capture_controller.dart';
import 'package:live_mix_master/audio/web/browser_mixer_controller.dart';
import 'package:live_mix_master/audio/web/browser_recording_controller.dart';
import 'package:live_mix_master/services/web/browser_fingerprint_lookup_controller.dart';
import 'package:live_mix_master/services/web/fingerprint_proxy_client.dart';

void main() {
  group('WebReferenceLiveState', () {
    test('maps verified W5 browser state without inventing unsupported telemetry', () {
      const capture = BrowserCaptureState(
        status: BrowserCaptureStatus.active,
        message: 'MICROPHONE CAPTURE ACTIVE',
        source: BrowserCaptureSource(
          kind: BrowserCaptureKind.microphone,
          id: 'mic-live',
          label: 'Booth Interface 1-2',
        ),
      );
      const mixer = BrowserMixerState(
        enabled: true,
        activeChannelId: 'mic-live',
        fader: .72,
        muted: false,
        solo: false,
        masterPeakLeft: .61,
        masterPeakRight: .83,
        limiterActive: true,
      );
      const recording = BrowserRecordingState(
        status: BrowserRecordingStatus.recording,
        message: 'RECORDING ACTIVE',
      );
      const fingerprint = BrowserFingerprintLookupState(
        status: BrowserFingerprintLookupStatus.matched,
        message: 'TRACK MATCH',
        track: FingerprintProxyTrack(
          artist: 'Live Artist',
          title: 'Live Title',
          release: null,
          providerId: 'provider-1',
          confidence: .91,
        ),
      );

      final state = WebReferenceLiveState.fromBrowserStates(
        capture: capture,
        mixer: mixer,
        recording: recording,
        fingerprint: fingerprint,
      );

      expect(state.captureActive, isTrue);
      expect(state.sourceId, 'mic-live');
      expect(state.sourceLabel, 'Booth Interface 1-2');
      expect(state.recordingActive, isTrue);
      expect(state.masterPeakLevel, .83);
      expect(state.limiterActive, isTrue);
      expect(state.currentArtist, 'Live Artist');
      expect(state.currentTrackTitle, 'Live Title');
      expect(state.matchConfidence, .91);
      expect(state.streamBitrateKbps, isNull);
      expect(state.loudnessLufs, isNull);
      expect(state.truePeakDbtp, isNull);
      expect(state.broadcastConfigured, isFalse);
      expect(state.isStreaming, isFalse);
    });

    test('uses explicit unavailable values before capture and before a track match', () {
      final state = WebReferenceLiveState.fromBrowserStates(
        capture: const BrowserCaptureState.idle(),
        mixer: const BrowserMixerState.disabled(),
        recording: const BrowserRecordingState.idle(),
        fingerprint: const BrowserFingerprintLookupState.idle(),
      );

      expect(state.captureActive, isFalse);
      expect(state.sourceId, isNull);
      expect(state.sourceLabel, 'NO ACTIVE SOURCE');
      expect(state.recordingActive, isFalse);
      expect(state.masterPeakLevel, 0);
      expect(state.limiterActive, isFalse);
      expect(state.currentArtist, 'UNKNOWN ARTIST');
      expect(state.currentTrackTitle, 'AWAITING TRACK DETECTION...');
      expect(state.matchConfidence, isNull);
      expect(state.streamBitrateKbps, isNull);
      expect(state.loudnessLufs, isNull);
      expect(state.truePeakDbtp, isNull);
      expect(state.broadcastConfigured, isFalse);
    });

    test('does not expose stale track metadata when lookup is not matched', () {
      const fingerprint = BrowserFingerprintLookupState(
        status: BrowserFingerprintLookupStatus.noMatch,
        message: 'NO MATCH',
        track: FingerprintProxyTrack(
          artist: 'Stale Artist',
          title: 'Stale Title',
          release: null,
          providerId: 'stale',
          confidence: .99,
        ),
      );

      final state = WebReferenceLiveState.fromBrowserStates(
        capture: const BrowserCaptureState.idle(),
        mixer: const BrowserMixerState.disabled(),
        recording: const BrowserRecordingState.idle(),
        fingerprint: fingerprint,
      );

      expect(state.currentArtist, 'UNKNOWN ARTIST');
      expect(state.currentTrackTitle, 'AWAITING TRACK DETECTION...');
      expect(state.matchConfidence, isNull);
    });
  });
}
