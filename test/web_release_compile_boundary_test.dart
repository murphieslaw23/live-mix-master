import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/app/app_surface_web.dart';
import 'package:live_mix_master/audio/audio_engine_factory.dart';
import 'package:live_mix_master/audio/audio_engine_port.dart';
import 'package:live_mix_master/audio/web/browser_capture_controller.dart';

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

  testWidgets('web shell drives browser source permission actions', (tester) async {
    final controller = BrowserCaptureController(gateway: _ShellGateway());

    await tester.pumpWidget(
      MaterialApp(home: WebReleaseShell(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('CONNECT MIC / USB'), findsOneWidget);
    expect(find.text('SHARE TAB / WINDOW'), findsOneWidget);
    expect(find.text('SOURCE PERMISSION REQUIRED'), findsWidgets);

    await tester.tap(find.text('CONNECT MIC / USB'));
    await tester.pumpAndSettle();

    expect(find.text('CAPTURE ACTIVE — USB INTERFACE'), findsOneWidget);
  });
}

class _ShellGateway implements BrowserMediaGateway {
  @override
  Future<BrowserAudioCapabilities> probeCapabilities() async {
    return const BrowserAudioCapabilities(
      mediaDevicesAvailable: true,
      microphoneCaptureAvailable: true,
      displayCaptureAvailable: true,
      systemAudioGuaranteed: false,
    );
  }

  @override
  Future<BrowserCaptureAttempt> requestMicrophone() async {
    return const BrowserCaptureAttempt.connected(
      BrowserCaptureSource(
        kind: BrowserCaptureKind.microphone,
        id: 'mic-test',
        label: 'USB INTERFACE',
      ),
    );
  }

  @override
  Future<BrowserCaptureAttempt> requestDisplayAudio() async {
    return const BrowserCaptureAttempt.noAudioTrack();
  }
}
