import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/design/live_mix_tokens.dart';
import 'package:live_mix_master/features/mixer/mixer_desk_view.dart';
import 'package:live_mix_master/features/monitor/compact_monitor_view.dart';

const _captureKey = ValueKey<String>('issue-5-golden-capture');

void main() {
  group('Issue #5 review golden fixtures', () {
    testWidgets('renders desktop mixer at 1440x1000', (tester) async {
      await _pumpCapture(tester, const Size(1440, 1000), const MixerDeskView());

      await expectLater(
        find.byKey(_captureKey),
        matchesGoldenFile('goldens/issue5-desktop-mixer-1440x1000.png'),
      );
    });

    testWidgets('renders tablet mixer at 1024x768', (tester) async {
      await _pumpCapture(tester, const Size(1024, 768), const MixerDeskView());

      await expectLater(
        find.byKey(_captureKey),
        matchesGoldenFile('goldens/issue5-tablet-mixer-1024x768.png'),
      );
    });

    testWidgets('renders phone field monitor at 390x844', (tester) async {
      await _pumpCapture(
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

      await expectLater(
        find.byKey(_captureKey),
        matchesGoldenFile('goldens/issue5-phone-monitor-390x844.png'),
      );
    });

    testWidgets('renders compact mixer with recording active at 760x640', (tester) async {
      await _pumpCapture(tester, const Size(760, 640), const MixerDeskView());
      await tester.tap(find.text('RECORD OFF'));
      await tester.pumpAndSettle();

      await expectLater(
        find.byKey(_captureKey),
        matchesGoldenFile('goldens/issue5-compact-recording-760x640.png'),
      );
    });
  });
}

Future<void> _pumpCapture(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      theme: LiveMixTheme.dark(),
      home: RepaintBoundary(
        key: _captureKey,
        child: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}
