import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/features/mixer/mixer_desk_view.dart';
import 'package:live_mix_master/services/fingerprint_service.dart';

void main() {
  group('LiveMixMaster End-to-End User Flow Tests', () {
    testWidgets('Complete DJ Session Workflow: Boot -> Route Strip -> Fingerprint -> Record', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: MixerDeskView(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('LIVEMIXMASTER'), findsOneWidget);
      expect(find.text('REKORDBOX'), findsOneWidget);
      expect(find.text('MASTER BUS'), findsOneWidget);

      final addInputButton = find.text('ADD INPUT');
      expect(addInputButton, findsOneWidget);
      await tester.tap(addInputButton);
      await tester.pumpAndSettle();

      expect(find.text('AUDIO PATCHBAY MATRIX & INPUT ROUTING'), findsOneWidget);
      expect(find.text('DISCOVERED AUDIO ENDPOINTS'), findsOneWidget);

      final attachButton = find.text('ATTACH CHANNEL STRIP');
      expect(attachButton, findsOneWidget);
      await tester.tap(attachButton);
      await tester.pumpAndSettle();

      expect(find.byType(MixerDeskView), findsOneWidget);

      final recordToggle = find.text('RECORD');
      expect(recordToggle, findsOneWidget);
      await tester.tap(recordToggle);
      await tester.pump();

      final playlistIconButton = find.byIcon(Icons.playlist_play);
      expect(playlistIconButton, findsOneWidget);
      await tester.tap(playlistIconButton);
      await tester.pumpAndSettle();

      expect(find.text('SESSION PLAYLIST'), findsOneWidget);
    });

    test('IdentifiedTrack JSON serialization and cue point format', () {
      final track = IdentifiedTrack(
        artist: 'System Corrupt',
        title: 'Tekno Totem',
        release: 'Subversion EP',
        acoustId: 'test-acoustid-uuid-1234',
        confidence: 0.94,
        detectedAt: DateTime(2026, 9, 8, 9, 30),
        sessionOffset: const Duration(minutes: 14, seconds: 22),
      );

      final json = track.toJson();
      expect(json['artist'], 'System Corrupt');
      expect(json['title'], 'Tekno Totem');
      expect(json['confidence'], 0.94);
      expect(json['sessionOffsetMs'], 862000);
    });
  });
}
