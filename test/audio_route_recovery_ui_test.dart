import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/audio_engine_bridge.dart';
import 'package:live_mix_master/design/live_mix_tokens.dart';
import 'package:live_mix_master/features/patchbay/audio_route_recovery_banner.dart';
import 'package:live_mix_master/features/patchbay/patchbay_routing_modal.dart';

void main() {
  group('actionable audio route recovery UI', () {
    testWidgets('patchbay distinguishes no-device from permission denial', (tester) async {
      var recoveryRequests = 0;
      await tester.pumpWidget(
        _host(
          PatchbayRoutingModal(
            endpoints: const <AudioEndpoint>[],
            routeState: AudioRouteState.noDevice,
            onRecoveryRequested: () => recoveryRequests += 1,
            onChannelConfigured: (_) {},
          ),
        ),
      );

      expect(find.text('NO AUDIO INPUTS DETECTED'), findsOneWidget);
      expect(find.text('REFRESH DEVICES'), findsOneWidget);
      expect(find.text('ATTACH CHANNEL STRIP'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'ATTACH CHANNEL STRIP'),
        ).onPressed,
        isNull,
      );
      await tester.tap(find.text('REFRESH DEVICES'));
      expect(recoveryRequests, 1);

      await tester.pumpWidget(
        _host(
          PatchbayRoutingModal(
            endpoints: const <AudioEndpoint>[],
            routeState: AudioRouteState.permissionDenied,
            onRecoveryRequested: () => recoveryRequests += 1,
            onChannelConfigured: (_) {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('AUDIO INPUT PERMISSION DENIED'), findsOneWidget);
      expect(find.text('OPEN AUDIO SETTINGS'), findsOneWidget);
      expect(find.text('NO AUDIO INPUTS DETECTED'), findsNothing);
    });

    testWidgets('route failures and recovery use explicit text plus operator action', (tester) async {
      const expectations = <AudioRouteState, (String, String?)>{
        AudioRouteState.noSignal: ('NO SIGNAL', 'RETRY ROUTE'),
        AudioRouteState.deviceLost: ('DEVICE LOST', 'REFRESH DEVICES'),
        AudioRouteState.formatError: ('FORMAT ERROR', 'RECONNECT'),
        AudioRouteState.overrun: ('AUDIO OVERRUN', 'RECONNECT'),
        AudioRouteState.recovered: ('ROUTE RECOVERED', null),
        AudioRouteState.failed: ('AUDIO ROUTE FAILED', 'RETRY ROUTE'),
      };

      for (final entry in expectations.entries) {
        await tester.pumpWidget(
          _host(
            AudioRouteRecoveryBanner(
              state: entry.key,
              onRecoveryRequested: () {},
            ),
          ),
        );
        await tester.pump();

        expect(find.text(entry.value.$1), findsOneWidget);
        final action = entry.value.$2;
        if (action != null) {
          expect(find.text(action), findsOneWidget);
        }
      }
    });
  });
}

Widget _host(Widget child) => MaterialApp(
      theme: LiveMixTheme.dark(),
      home: Scaffold(body: Center(child: child)),
    );
