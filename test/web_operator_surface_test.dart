import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/app/app_surface_web.dart';
import 'package:live_mix_master/audio/web/browser_capture_controller.dart';
import 'package:live_mix_master/audio/web/browser_mixer_controller.dart';
import 'package:live_mix_master/audio/web/browser_mixer_protocol.dart';
import 'package:live_mix_master/audio/web/browser_recording_controller.dart';
import 'package:live_mix_master/services/reliability_models.dart';
import 'package:live_mix_master/services/session_tracklist_repository.dart';
import 'package:live_mix_master/services/web/browser_session_controller.dart';

void main() {
  testWidgets('web operator surface exposes mixer controls, telemetry, disconnect, and durable session actions', (tester) async {
    final captureGateway = _CaptureGateway();
    final captureController = BrowserCaptureController(gateway: captureGateway);
    final mixerGateway = _MixerGateway();
    final mixerController = BrowserMixerController(gateway: mixerGateway);
    final repository = _MemoryRepository(<TracklistEntry>[
      TracklistEntry(
        sessionId: 'session-1',
        cueTime: const Duration(seconds: 12),
        sourceId: 'browser-master',
        artist: 'Recovered Artist',
        title: 'Recovered Title',
        confidence: 1,
        provenance: TrackProvenance.manual,
        createdAt: DateTime.utc(2026, 9, 11, 10),
        updatedAt: DateTime.utc(2026, 9, 11, 10, 1),
      ),
    ]);
    final downloads = _DownloadGateway();
    final sessionController = BrowserSessionController(
      repository: repository,
      downloadGateway: downloads,
      clock: () => DateTime.utc(2026, 9, 11, 11),
    );
    final recordingController = BrowserRecordingController(
      gateway: _RecordingGateway(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WebReleaseShell(
          controller: captureController,
          recordingController: recordingController,
          mixerController: mixerController,
          sessionController: sessionController,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tapVisible(tester, 'CONNECT MIC / USB');
    await mixerController.attach('mic-test');
    await tester.pump();

    expect(find.text('Channel fader'), findsOneWidget);
    expect(find.text('Mute'), findsOneWidget);
    expect(find.text('Solo'), findsOneWidget);
    expect(find.text('Channel peak'), findsOneWidget);
    expect(find.text('Channel RMS'), findsOneWidget);
    expect(find.text('Master peak'), findsOneWidget);
    expect(find.text('Limiter'), findsOneWidget);
    expect(find.text('Disconnect source'), findsOneWidget);

    final slider = tester.widget<Slider>(find.byKey(const ValueKey('channel-fader')));
    slider.onChanged!(0.4);
    await tester.pump();
    expect(mixerController.state.fader, closeTo(0.4, 0.0001));

    await _tapVisible(tester, 'Mute');
    expect(mixerController.state.muted, isTrue);
    await _tapVisible(tester, 'Solo');
    expect(mixerController.state.solo, isTrue);

    mixerGateway.publish(
      const BrowserMixerTelemetry(
        channelMeters: <String, BrowserChannelMeter>{
          'mic-test': BrowserChannelMeter(
            peakLeft: 0.5,
            peakRight: 0.4,
            rmsLeft: 0.25,
            rmsRight: 0.2,
            clipping: false,
          ),
        },
        masterPeakLeft: 0.45,
        masterPeakRight: 0.35,
        limiterActive: false,
      ),
    );
    await _pumpBounded(tester);
    expect(find.textContaining('0.500'), findsOneWidget);
    expect(find.textContaining('0.250'), findsOneWidget);
    expect(find.textContaining('0.450'), findsOneWidget);
    _stage('telemetry-verified');

    expect(find.text('Session tracklist'), findsOneWidget);
    expect(find.text('Recovered Artist'), findsOneWidget);
    expect(find.text('Recovered Title'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('session-artist-0')),
      'Corrected Artist',
    );
    await tester.enterText(
      find.byKey(const ValueKey('session-title-0')),
      'Corrected Title',
    );
    _stage('session-fields-entered');
    await _tapVisible(tester, 'Save correction');
    _stage('session-save-tapped');

    expect(repository.saved.single.artist, 'Corrected Artist');
    expect(repository.saved.single.title, 'Corrected Title');
    expect(repository.saved.single.provenance, TrackProvenance.manual);
    _stage('session-save-verified');

    await _tapVisible(tester, 'Export session JSON');
    _stage('json-exported');
    await _tapVisible(tester, 'Export session CSV');
    _stage('csv-exported');
    await _tapVisible(tester, 'Export session M3U');
    _stage('m3u-exported');
    expect(downloads.fileNames, hasLength(3));
    expect(downloads.fileNames[0], endsWith('.json'));
    expect(downloads.contents[0], contains('Corrected Artist'));
    expect(downloads.fileNames[1], endsWith('.csv'));
    expect(downloads.fileNames[2], endsWith('.m3u'));
    _stage('exports-verified');

    await _tapVisible(tester, 'Disconnect source');
    _stage('disconnect-tapped');
    expect(captureGateway.disconnectCalls, 1);
    expect(captureController.state.status, BrowserCaptureStatus.reconnectRequired);
    _stage('disconnect-verified');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    _stage('shell-unmounted');
    await mixerController.dispose();
    _stage('mixer-controller-disposed');
    await tester.runAsync(() async {
      await mixerGateway.dispose();
      _stage('mixer-gateway-disposed');
      await sessionController.dispose();
      _stage('session-controller-disposed');
    });
  });
}

void _stage(String value) {
  debugPrint('WEB_OPERATOR_STAGE: $value');
}

Future<void> _tapVisible(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await _pumpBounded(tester);
  await tester.tap(target);
  await _pumpBounded(tester);
}

Future<void> _pumpBounded(WidgetTester tester) async {
  for (var frame = 0; frame < 4; frame += 1) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

class _CaptureGateway
    implements BrowserMediaGateway, BrowserMediaDisconnectGateway {
  int disconnectCalls = 0;

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

  @override
  void disconnectActiveStream() {
    disconnectCalls += 1;
  }
}

class _MixerGateway implements BrowserMixerGateway {
  final StreamController<BrowserMixerTelemetry> _telemetry =
      StreamController<BrowserMixerTelemetry>.broadcast(sync: true);

  @override
  Stream<BrowserMixerTelemetry> get telemetry => _telemetry.stream;

  @override
  Future<void> configure(BrowserMixerConfiguration configuration) async {}

  void publish(BrowserMixerTelemetry telemetry) => _telemetry.add(telemetry);

  Future<void> dispose() => _telemetry.close();
}

class _RecordingGateway implements BrowserRecordingGateway {
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
  Future<void> exportRecording(BrowserRecordingArtifact artifact) async {}
}

class _MemoryRepository implements SessionTracklistRepository {
  _MemoryRepository(List<TracklistEntry> entries)
      : _entries = List<TracklistEntry>.of(entries);

  final StreamController<ServiceStatus> _statuses =
      StreamController<ServiceStatus>.broadcast();
  List<TracklistEntry> _entries;
  List<TracklistEntry> saved = const <TracklistEntry>[];

  @override
  Stream<ServiceStatus> get onStatus => _statuses.stream;

  @override
  Future<List<TracklistEntry>> load() async => List<TracklistEntry>.of(_entries);

  @override
  Future<void> save(Iterable<TracklistEntry> entries) async {
    saved = List<TracklistEntry>.of(entries);
    _entries = List<TracklistEntry>.of(entries);
    _statuses.add(const ServiceStatus.succeeded());
  }

  @override
  Future<void> dispose() => _statuses.close();
}

class _DownloadGateway implements BrowserTracklistDownloadGateway {
  final List<String> fileNames = <String>[];
  final List<String> contents = <String>[];

  @override
  Future<void> download({
    required String fileName,
    required String mimeType,
    required String contents,
  }) async {
    fileNames.add(fileName);
    this.contents.add(contents);
  }
}
