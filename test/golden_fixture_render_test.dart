import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/design/live_mix_tokens.dart';
import 'package:live_mix_master/features/mixer/mixer_desk_view.dart';
import 'package:live_mix_master/features/monitor/compact_monitor_view.dart';

const _captureKey = ValueKey<String>('issue-5-golden-capture');
bool _approvedFontsLoaded = false;

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
          isStreaming: false,
          isRecording: true,
          currentTrackTitle: 'FORWARD THE REVOLUTION',
          currentArtist: 'SPIRAL TRIBE',
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

Future<void> _loadApprovedFonts() async {
  if (_approvedFontsLoaded) return;

  final bundledFonts = <(String, String)>[
    ('Roboto Condensed', 'assets/fonts/RobotoCondensed-Variable.ttf'),
    ('Inter', 'assets/fonts/Inter-Variable.ttf'),
    ('Roboto Mono', 'assets/fonts/RobotoMono-Variable.ttf'),
  ];

  for (final (family, asset) in bundledFonts) {
    final loader = FontLoader(family)..addFont(rootBundle.load(asset));
    await loader.load();
  }

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null || flutterRoot.isEmpty) {
    throw StateError('FLUTTER_ROOT is required for deterministic Material Icons goldens');
  }

  final iconFont = File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  final iconBytes = Future<ByteData>.value(
    iconFont.readAsBytesSync().buffer.asByteData(),
  );
  await (FontLoader('MaterialIcons')..addFont(iconBytes)).load();

  _approvedFontsLoaded = true;
}

Future<void> _pumpCapture(WidgetTester tester, Size size, Widget child) async {
  await _loadApprovedFonts();

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
