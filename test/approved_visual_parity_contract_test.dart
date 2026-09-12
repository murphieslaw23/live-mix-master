import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/app/app_surface.dart';
import 'package:live_mix_master/design/live_mix_tokens.dart';
import 'package:live_mix_master/features/mixer/mixer_desk_view.dart';
import 'package:live_mix_master/features/monitor/compact_monitor_view.dart';

void main() {
  group('approved Issue #1 visual parity anchors', () {
    testWidgets('desktop mixer exposes approved channel, master and fingerprint hierarchy', (tester) async {
      await _pumpAt(tester, const Size(1440, 1000), const MixerDeskView());

      for (final label in <String>['USB 1-2', 'REKORDBOX', 'MIC 1', 'AUX']) {
        expect(find.text(label), findsOneWidget, reason: 'missing approved channel: $label');
      }

      for (final label in <String>[
        'LOUDNESS',
        '-14.2 LUFS',
        'TRUE PEAK',
        '-6.0 dBTP',
        'ARTIST',
        'TITLE',
        'MATCH',
        'CORRECT',
        'VIEW SESSION',
      ]) {
        expect(find.text(label), findsWidgets, reason: 'missing approved desktop anchor: $label');
      }

      expect(tester.takeException(), isNull);
    });

    testWidgets('web release shell uses the approved rack and master hierarchy', (tester) async {
      await _pumpAt(tester, const Size(1440, 1000), buildPrimaryOperatorSurface());

      expect(
        find.byKey(const ValueKey('web-reference-shell')),
        findsOneWidget,
        reason: 'Vercel web release must expose the approved reference composition root',
      );

      for (final label in <String>[
        'LIVE MIX',
        'SOURCE CHANNEL',
        'MASTER STEREO',
        'LOUDNESS',
        'TRUE PEAK',
        'BROADCAST',
      ]) {
        expect(
          find.text(label),
          findsWidgets,
          reason: 'missing approved Vercel reference anchor: $label',
        );
      }

      expect(tester.takeException(), isNull);
    });

    testWidgets('phone monitor exposes approved recovery, track and source hierarchy', (tester) async {
      await _pumpAt(
        tester,
        const Size(390, 844),
        const CompactMonitorView(
          isStreaming: false,
          isRecording: true,
          currentTrackTitle: 'FORWARD THE REVOLUTION',
          currentArtist: 'SPIRAL TRIBE',
          streamBitrateKbps: 320,
          masterPeakLevel: .84,
        ),
      );

      for (final label in <String>[
        'LIVEMIXMASTER',
        'WAREHOUSE 023',
        'FIELD MONITOR',
        'Read-only monitor',
        'LOUDNESS',
        '-14.2 LUFS',
        'TRUE PEAK',
        '-6.0 dBTP',
        'RECONNECTING',
        'Attempt 2 of 5',
        'Local recording continues',
        'CURRENT TRACK',
        'ARTIST',
        'TITLE',
        'MATCH',
        'USB 1-2',
        'REKORDBOX',
        'MIC 1',
        'AUX',
        'MONITOR',
        'SESSION',
      ]) {
        expect(find.text(label), findsWidgets, reason: 'missing approved phone anchor: $label');
      }

      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      theme: LiveMixTheme.dark(),
      home: child,
    ),
  );
  await tester.pumpAndSettle();
}
