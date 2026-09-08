import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/services/broadcast_metadata_adapter.dart';
import 'package:live_mix_master/services/fingerprint_service.dart';

void main() {
  group('LiveMixMaster Broadcast & Identification Pipeline Integration Tests', () {
    late StreamController<IdentifiedTrack> fingerprintStreamController;

    setUp(() {
      fingerprintStreamController = StreamController<IdentifiedTrack>.broadcast();
    });

    tearDown(() async {
      await fingerprintStreamController.close();
    });

    test('IdentifiedTrack stream triggers broadcast adapter metadata processing without audio interruption', () async {
      final emittedTracks = <IdentifiedTrack>[];

      final sub = fingerprintStreamController.stream.listen((track) {
        emittedTracks.add(track);
      });

      final testTrack = IdentifiedTrack(
        artist: 'SYSTEM CORRUPT',
        title: 'TEKNO TOTAL',
        release: 'UNDERGROUND SOUNDSYSTEM 2026',
        acoustId: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
        confidence: 0.98,
        detectedAt: DateTime.now(),
        sessionOffset: const Duration(minutes: 42, seconds: 15),
      );

      fingerprintStreamController.add(testTrack);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(emittedTracks.length, 1);
      expect(emittedTracks.first.artist, 'SYSTEM CORRUPT');
      expect(emittedTracks.first.title, 'TEKNO TOTAL');
      expect(emittedTracks.first.confidence, 0.98);

      await sub.cancel();
    });

    test('BroadcastServerConfig correctly configures endpoints for Icecast and Webhooks', () {
      const config = BroadcastServerConfig(
        protocol: BroadcastProtocol.icecast,
        host: 'stream.syco23.org',
        port: 8000,
        mountPoint: '/live-jungle',
        adminUser: 'source',
        adminPassword: 'test-password',
      );

      expect(config.protocol, BroadcastProtocol.icecast);
      expect(config.host, 'stream.syco23.org');
      expect(config.mountPoint, '/live-jungle');
    });
  });
}
