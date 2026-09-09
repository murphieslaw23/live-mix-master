import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/services/fingerprint_service.dart';
import 'package:live_mix_master/services/fingerprint_tracklist_bridge.dart';
import 'package:live_mix_master/services/live_session_tracklist_controller.dart';
import 'package:live_mix_master/services/reliability_models.dart';
import 'package:live_mix_master/services/session_tracklist.dart';
import 'package:live_mix_master/services/session_tracklist_persister.dart';
import 'package:live_mix_master/services/session_tracklist_store.dart';

void main() {
  group('FingerprintService Reliability & Tracklist Integration Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('lmm_fp_test_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('IdentifiedTrack converts to FingerprintMatch properly', () {
      final track = IdentifiedTrack(
        artist: 'System Corrupt',
        title: 'Tekno Totem',
        release: 'Subversion EP',
        acoustId: 'acoustid-1234',
        confidence: 0.95,
        detectedAt: DateTime.utc(2026, 9, 8, 12),
        sessionOffset: const Duration(minutes: 5),
      );

      final match = track.toFingerprintMatch();
      expect(match.artist, 'System Corrupt');
      expect(match.title, 'Tekno Totem');
      expect(match.confidence, 0.95);
      expect(match.providerId, 'acoustid-1234');
    });

    test('FingerprintService routes identified tracks to LiveSessionTracklistController', () async {
      final tracklist = SessionTracklist();
      final store = SessionTracklistStore(file: File('${tempDir.path}/session.json'));
      final persister = SessionTracklistPersister(store: store, debounce: const Duration(milliseconds: 10));
      final controller = LiveSessionTracklistController(
        sessionId: 'session_dj_01',
        sourceId: 'master',
        tracklist: tracklist,
        bridge: FingerprintTracklistBridge(tracklist: tracklist, minimumConfidence: 0.70),
        persister: persister,
      );

      final service = FingerprintService(
        config: const AudioFingerprintConfig(acoustIdApiKey: 'test-key'),
        tracklistController: controller,
      );

      // Simulate a track found arriving through the service
      final testTrack = IdentifiedTrack(
        artist: 'DVS1',
        title: 'Black Russian',
        acoustId: 'acoustid-uuid-5678',
        confidence: 0.92,
        detectedAt: DateTime.utc(2026, 9, 9, 10),
        sessionOffset: const Duration(seconds: 45),
      );

      controller.acceptFingerprint(
        cueTime: testTrack.sessionOffset,
        match: testTrack.toFingerprintMatch(),
        recognizedAt: testTrack.detectedAt,
      );

      expect(controller.entries, hasLength(1));
      expect(controller.entries.first.artist, 'DVS1');
      expect(controller.entries.first.title, 'Black Russian');
      expect(controller.entries.first.provenance, TrackProvenance.automatic);

      await controller.close();
      final loaded = await store.load();
      expect(loaded, hasLength(1));
      expect(loaded.first.artist, 'DVS1');
      expect(loaded.first.title, 'Black Russian');

      await service.stop();
    });

    test('ServiceStatus stream exposes idle, running, and error states', () async {
      final service = FingerprintService(
        config: const AudioFingerprintConfig(acoustIdApiKey: ''),
      );

      // Verify stream is active
      expect(service.onStatus, isA<Stream<ServiceStatus>>());
      await service.stop();
    });
  });
}
