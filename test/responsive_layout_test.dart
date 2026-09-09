import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/design/live_mix_tokens.dart';
import 'package:live_mix_master/features/mixer/mixer_desk_view.dart';
import 'package:live_mix_master/features/monitor/compact_monitor_view.dart';

void main() {
  group('operator surface responsive layout contract', () {
    testWidgets('desktop mixer remains overflow-free with fixed master bus', (tester) async {
      await _pumpAt(tester, const Size(1440, 1000), const MixerDeskView());

      expect(find.text('LIVEMIXMASTER'), findsOneWidget);
      expect(find.text('MASTER BUS'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tablet landscape mixer preserves routing and master hierarchy', (tester) async {
      await _pumpAt(tester, const Size(1024, 768), const MixerDeskView());

      expect(find.text('ADD INPUT'), findsOneWidget);
      expect(find.text('MASTER BUS'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('phone portrait field monitor keeps live telemetry readable', (tester) async {
      await _pumpAt(
        tester,
        const Size(390, 844),
        const CompactMonitorView(
          isStreaming: true,
          isRecording: true,
          currentTrackTitle: 'TEKNO TOTEM',
          currentArtist: 'SYSTEM CORRUPT',
          streamBitrateKbps: 320,
          masterPeakLevel: .84,
        ),
      );

      expect(find.text('FIELD MONITOR'), findsOneWidget);
      expect(find.text('TEKNO TOTEM'), findsOneWidget);
      expect(find.text('SYSTEM CORRUPT'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('compact mixer remains usable after recording state expands the top bar', (tester) async {
      await _pumpAt(tester, const Size(760, 640), const MixerDeskView());

      await tester.tap(find.text('RECORD OFF'));
      await tester.pumpAndSettle();

      expect(find.text('RECORD ON'), findsOneWidget);
      expect(find.text('MASTER BUS'), findsOneWidget);
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
