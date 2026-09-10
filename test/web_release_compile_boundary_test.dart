import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/app/app_surface_web.dart';
import 'package:live_mix_master/audio/audio_engine_factory.dart';
import 'package:live_mix_master/audio/audio_engine_port.dart';

void main() {
  test('VM bootstrap selects the desktop native backend', () {
    final port = createAudioEnginePort();

    expect(port.kind, AudioEngineKind.desktopNative);
  });

  test('bootstrap result is platform-neutral', () {
    const result = AudioEngineBootstrapResult.available(
      kind: AudioEngineKind.webBrowser,
      message: 'Browser audio backend ready',
    );

    expect(result.isAvailable, isTrue);
    expect(result.kind, AudioEngineKind.webBrowser);
    expect(result.message, 'Browser audio backend ready');
    expect(result.diagnostics, isEmpty);
  });

  testWidgets('web shell states browser audio limitations explicitly', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: WebReleaseShell()),
    );

    expect(find.text('WEB AUDIO'), findsOneWidget);
    expect(find.text('SOURCE PERMISSION REQUIRED'), findsOneWidget);
    expect(find.text('MIC / USB INPUT'), findsOneWidget);
    expect(find.text('TAB / WINDOW AUDIO'), findsOneWidget);
    expect(find.text('SYSTEM AUDIO'), findsOneWidget);
    expect(find.text('BROWSER / OS DEPENDENT'), findsOneWidget);
  });
}
