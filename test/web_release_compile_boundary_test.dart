import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/app/app_surface_web.dart';
import 'package:live_mix_master/audio/audio_engine_factory.dart';
import 'package:live_mix_master/audio/audio_engine_port.dart';
import 'package:live_mix_master/audio/web/browser_capture_controller.dart';
import 'package:live_mix_master/audio/web/browser_recording_controller.dart';

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

  test('session persistence keeps dart:io behind the desktop store boundary', () {
    final repository = File(
      'lib/services/session_tracklist_repository.dart',
    ).readAsStringSync();
    final persister = File(
      'lib/services/session_tracklist_persister.dart',
    ).readAsStringSync();
    final desktopStore = File(
      'lib/services/session_tracklist_store.dart',
    ).readAsStringSync();
    final browserStore = File(
      'lib/services/web/browser_session_tracklist_repository.dart',
    ).readAsStringSync();

    expect(repository, isNot(contains('dart:io')));
    expect(persister, contains("import 'session_tracklist_repository.dart';"));
    expect(persister, isNot(contains("import 'session_tracklist_store.dart';")));
    expect(browserStore, isNot(contains('dart:io')));
    expect(browserStore, isNot(contains('session_tracklist_store.dart')));
    expect(desktopStore, contains("import 'dart:io';"));
    expect(
      desktopStore,
      contains('implements SessionTracklistRepository'),
    );
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

    await _tapVisible(tester, 'CONNECT MIC / USB');

    expect(find.text('CAPTURE ACTIVE — USB INTERFACE'), findsOneWidget);
  });

  testWidgets('web shell reacts to ended lifecycle without another user action', (tester) async {
    final gateway = _LifecycleShellGateway();
    final controller = BrowserCaptureController(gateway: gateway);

    await tester.pumpWidget(
      MaterialApp(home: WebReleaseShell(controller: controller)),
    );
    await tester.pumpAndSettle();
    await _tapVisible(tester, 'CONNECT MIC / USB');

    expect(find.text('CAPTURE ACTIVE — USB INTERFACE'), findsOneWidget);

    gateway.endActiveTrack();
    await tester.pump();

    expect(
      find.text('CAPTURE ENDED / ACCESS REVOKED — RECONNECT REQUIRED'),
      findsOneWidget,
    );
  });

  testWidgets('web shell surfaces device inventory change while retaining source', (tester) async {
    final gateway = _LifecycleShellGateway();
    final controller = BrowserCaptureController(gateway: gateway);

    await tester.pumpWidget(
      MaterialApp(home: WebReleaseShell(controller: controller)),
    );
    await tester.pumpAndSettle();
    await _tapVisible(tester, 'CONNECT MIC / USB');

    gateway.changeDeviceInventory();
    await tester.pump();

    expect(
      find.text('AUDIO DEVICE LIST CHANGED — VERIFY SOURCE / RECONNECT IF NEEDED'),
      findsOneWidget,
    );
  });

  testWidgets('web shell drives explicit record stop and download operator flow', (tester) async {
    final captureController = BrowserCaptureController(gateway: _ShellGateway());
    final recordingGateway = _ShellRecordingGateway();
    final recordingController = BrowserRecordingController(gateway: recordingGateway);

    await tester.pumpWidget(
      MaterialApp(
        home: WebReleaseShell(
          controller: captureController,
          recordingController: recordingController,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('START RECORDING'), findsOneWidget);

    await _tapVisible(tester, 'CONNECT MIC / USB');
    await _tapVisible(tester, 'START RECORDING');

    expect(find.text('RECORDING ACTIVE — POST-MASTER PCM TO WAV'), findsOneWidget);
    expect(find.text('STOP RECORDING'), findsOneWidget);

    await _tapVisible(tester, 'STOP RECORDING');

    expect(find.text('WAV FINALIZED — acceptance.wav — 50 BYTES'), findsOneWidget);
    expect(find.text('DOWNLOAD WAV'), findsOneWidget);

    await _tapVisible(tester, 'DOWNLOAD WAV');

    expect(recordingGateway.exports, 1);
    expect(find.text('WAV DOWNLOAD REQUESTED — acceptance.wav'), findsOneWidget);
  });
}

Future<void> _tapVisible(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
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

class _LifecycleShellGateway extends _ShellGateway
    implements BrowserMediaLifecycleGateway {
  void Function()? _onEnded;
  void Function()? _onDeviceChange;

  @override
  void setTrackEndedHandler(void Function() handler) {
    _onEnded = handler;
  }

  @override
  void setDeviceChangeHandler(void Function() handler) {
    _onDeviceChange = handler;
  }

  void endActiveTrack() => _onEnded?.call();

  void changeDeviceInventory() => _onDeviceChange?.call();
}

class _ShellRecordingGateway implements BrowserRecordingGateway {
  int exports = 0;

  @override
  Future<void> startRecording() async {}

  @override
  Future<BrowserRecordingArtifact> stopRecording() async {
    return const BrowserRecordingArtifact(
      fileName: 'acceptance.wav',
      bytesWritten: 50,
      dataBytes: 6,
    );
  }

  @override
  Future<void> exportRecording(BrowserRecordingArtifact artifact) async {
    exports += 1;
  }
}
