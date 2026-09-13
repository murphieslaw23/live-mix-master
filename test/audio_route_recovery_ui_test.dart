import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/audio_engine_bridge.dart';
import 'package:live_mix_master/design/live_mix_tokens.dart';
import 'package:live_mix_master/features/patchbay/audio_route_recovery_banner.dart';

void main() {
  testWidgets('permission denial exposes settings and explicit refresh actions',
      (tester) async {
    var openSettings = 0;
    var refresh = 0;

    await tester.pumpWidget(
      _host(
        AudioRouteRecoveryBanner(
          state: AudioRouteState.permissionDenied,
          onRecoveryRequested: () => openSettings += 1,
          onRefreshRequested: () => refresh += 1,
        ),
      ),
    );

    expect(find.text('AUDIO INPUT PERMISSION DENIED'), findsOneWidget);
    expect(find.text('OPEN AUDIO SETTINGS'), findsOneWidget);
    expect(find.text('REFRESH ACCESS'), findsOneWidget);

    await tester.tap(find.text('OPEN AUDIO SETTINGS'));
    expect(openSettings, 1);
    expect(refresh, 0);

    await tester.tap(find.text('REFRESH ACCESS'));
    expect(openSettings, 1);
    expect(refresh, 1);
  });

  testWidgets('other recovery states keep explicit operator actions',
      (tester) async {
    const expectations = <AudioRouteState, (String, String?)>{
      AudioRouteState.noDevice: ('NO AUDIO INPUTS DETECTED', 'REFRESH DEVICES'),
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
      if (entry.value.$2 case final action?) {
        expect(find.text(action), findsOneWidget);
      }
    }
  });
}

Widget _host(Widget child) => MaterialApp(
      theme: LiveMixTheme.dark(),
      home: Scaffold(body: Center(child: child)),
    );
