import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/app/app_surface_web_reference.dart' as web_surface;
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

    testWidgets('web release shell keeps approved hierarchy without fixture telemetry claims', (tester) async {
      await _pumpAt(
        tester,
        const Size(1440, 1000),
        web_surface.buildPrimaryOperatorSurface(),
      );

      expect(
        find.byKey(const ValueKey('web-reference-shell')),
        findsOneWidget,
        reason: 'Vercel web release must expose the approved reference composition root',
      );

      for (final label in <String>[
        'LIVEMIXMASTER',
        'NO ACTIVE SOURCE',
        'MASTER BUS',
        'LOUDNESS',
        'TRUE PEAK',
        'BROADCAST',
        'UNAVAILABLE',
      ]) {
        expect(
          find.text(label),
          findsWidgets,
          reason: 'missing truthful Vercel reference anchor: $label',
        );
      }

      for (final fixtureOnlyLabel in <String>[
        'USB 1-2',
        'REKORDBOX',
        'MIC 1',
        'AUX',
        '-14.2 LUFS',
        '-6.0 dBTP',
        '320 KBPS',
      ]) {
        expect(
          find.text(fixtureOnlyLabel),
          findsNothing,
          reason: 'production Web shell must not expose fixture-only state: $fixtureOnlyLabel',
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
          broadcastConfigured: true,
          isRecording: true,
          currentTrackTitle: 'FORWARD THE REVOLUTION',
          currentArtist: 'SPIRAL TRIBE',
          streamBitrateKbps: 320,
          masterPeakLevel: .84,
          matchConfidence: .94,
          loudnessLufs: -14.2,
          truePeakDbtp: -6.0,
          limiterActive: true,
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
        'OFFLINE',
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