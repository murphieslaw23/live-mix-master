import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/design/live_mix_tokens.dart';
import 'package:live_mix_master/design/widgets/lmm_controls.dart';

void main() {
  group('LiveMixMaster shared design-system semantics', () {
    testWidgets('toggle has an explicit state, 44px target and keyboard activation', (tester) async {
      var value = false;
      await tester.pumpWidget(_host(
        StatefulBuilder(
          builder: (context, setState) => LmmToggleControl(
            key: const Key('mute-toggle'),
            label: 'MUTE',
            value: value,
            onChanged: (next) => setState(() => value = next),
          ),
        ),
      ));

      expect(find.text('MUTE OFF'), findsOneWidget);
      final size = tester.getSize(find.byKey(const Key('mute-toggle')));
      expect(size.width, greaterThanOrEqualTo(LiveMixTokens.minimumTarget));
      expect(size.height, greaterThanOrEqualTo(LiveMixTokens.minimumTarget));

      final semantics = tester.getSemantics(find.byKey(const Key('mute-toggle')));
      expect(semantics.label, contains('MUTE'));
      expect(semantics.value, 'OFF');
      expect(semantics.hasAction(SemanticsAction.tap), isTrue);

      await tester.tap(find.byKey(const Key('mute-toggle')));
      await tester.pump();
      expect(find.text('MUTE ON'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text('MUTE OFF'), findsOneWidget);
    });

    testWidgets('disabled toggle remains labeled but cannot activate', (tester) async {
      await tester.pumpWidget(_host(
        const LmmToggleControl(
          key: Key('disabled-toggle'),
          label: 'SOLO',
          value: false,
          onChanged: null,
        ),
      ));

      final semantics = tester.getSemantics(find.byKey(const Key('disabled-toggle')));
      expect(semantics.label, contains('SOLO'));
      expect(semantics.value, 'OFF');
      expect(semantics.hasAction(SemanticsAction.tap), isFalse);
      expect(find.text('SOLO OFF'), findsOneWidget);
    });

    testWidgets('status badge reinforces state with icon text shape and semantic copy', (tester) async {
      await tester.pumpWidget(_host(
        const LmmStatusBadge(
          key: Key('broadcast-status'),
          label: 'BROADCAST',
          status: 'LIVE',
          detail: 'CONNECTED',
          tone: LmmStatusTone.healthy,
          icon: Icons.wifi_tethering,
        ),
      ));

      expect(find.byIcon(Icons.wifi_tethering), findsOneWidget);
      expect(find.text('BROADCAST'), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);
      final semantics = tester.getSemantics(find.byKey(const Key('broadcast-status')));
      expect(semantics.label, contains('BROADCAST'));
      expect(semantics.value, contains('LIVE'));
      expect(semantics.value, contains('CONNECTED'));
    });

    testWidgets('stereo meter exposes semantic channel values and canonical scale', (tester) async {
      await tester.pumpWidget(_host(
        const LmmStereoMeter(
          key: Key('master-meter'),
          label: 'MASTER',
          leftDbfs: -12,
          rightDbfs: -6,
        ),
      ));

      expect(find.text('MASTER'), findsOneWidget);
      for (final tick in LiveMixTokens.meterScaleDbfs) {
        expect(find.text('${tick.toInt()}'), findsWidgets);
      }
      expect(find.text('-12.0 dBFS'), findsOneWidget);
      expect(find.text('-6.0 dBFS'), findsOneWidget);
      expect(find.bySemanticsLabel('MASTER left meter'), findsOneWidget);
      expect(find.bySemanticsLabel('MASTER right meter'), findsOneWidget);
    });

    testWidgets('device and preflight states never rely on color alone', (tester) async {
      await tester.pumpWidget(_host(
        const Column(
          children: [
            LmmDeviceStatus(
              label: 'USB INTERFACE',
              state: LmmDeviceState.lost,
            ),
            LmmPreflightCheck(
              label: 'BROADCAST CREDENTIALS',
              state: LmmPreflightState.error,
              detail: 'INVALID CREDENTIALS',
            ),
          ],
        ),
      ));

      expect(find.text('DEVICE LOST'), findsOneWidget);
      expect(find.text('ERROR'), findsOneWidget);
      expect(find.text('INVALID CREDENTIALS'), findsOneWidget);
      expect(find.byIcon(Icons.link_off), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('fader exposes semantic value and minimum interactive width', (tester) async {
      var value = 0.5;
      await tester.pumpWidget(_host(
        StatefulBuilder(
          builder: (context, setState) => LmmFader(
            key: const Key('master-fader'),
            label: 'MASTER FADER',
            value: value,
            onChanged: (next) => setState(() => value = next),
          ),
        ),
      ));

      final size = tester.getSize(find.byKey(const Key('master-fader')));
      expect(size.width, greaterThanOrEqualTo(LiveMixTokens.minimumTarget));
      final semantics = tester.getSemantics(find.byKey(const Key('master-fader')));
      expect(semantics.label, contains('MASTER FADER'));
      expect(semantics.value, contains('50'));
    });
  });
}

Widget _host(Widget child) => MaterialApp(
  theme: LiveMixTheme.dark(),
  home: Scaffold(body: Center(child: child)),
);
