import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/app/app_surface_web.dart';
import 'package:live_mix_master/audio/web/browser_capture_controller.dart';
import 'package:live_mix_master/audio/web/browser_mixer_controller.dart';
import 'package:live_mix_master/audio/web/browser_mixer_protocol.dart';
import 'package:live_mix_master/audio/web/browser_recording_controller.dart';
import 'package:live_mix_master/services/reliability_models.dart';
import 'package:live_mix_master/services/web/browser_session_controller.dart';
import 'package:live_mix_master/services/web/fingerprint_proxy_client.dart';

void main() {
  testWidgets(
      'web operator surface exposes mixer controls, telemetry, disconnect, and durable session actions',
      (tester) async {
    final captureGateway = _CaptureGateway();
    final captureController = BrowserCaptureController(gateway: captureGateway);
    final mixerController = _SurfaceMixerController();
    final sessionPort = _SessionPort(
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
          sessionController: sessionPort,
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

    final slider =
        tester.widget<Slider>(find.byKey(const ValueKey('channel-fader')));
    slider.onChanged!(0.4);
    await tester.pump();
    expect(mixerController.state.fader, closeTo(0.4, 0.0001));

    await _tapVisible(tester, 'Mute');
    expect(mixerController.state.muted, isTrue);
    await _tapVisible(tester, 'Solo');
    expect(mixerController.state.solo, isTrue);

    mixerController.publish(
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

    expect(sessionPort.state.entries.single.artist, 'Corrected Artist');
    expect(sessionPort.state.entries.single.title, 'Corrected Title');
    expect(
      sessionPort.state.entries.single.provenance,
      TrackProvenance.manual,
    );
    _stage('session-save-verified');

    await _tapVisible(tester, 'Export session JSON');
    _stage('json-exported');
    await _tapVisible(tester, 'Export session CSV');
    _stage('csv-exported');
    await _tapVisible(tester, 'Export session M3U');
    _stage('m3u-exported');
    expect(sessionPort.exportCalls, <String>['json', 'csv', 'm3u']);
    _stage('exports-verified');

    await _tapVisible(tester, 'Disconnect source');
    _stage('disconnect-tapped');
    expect(captureGateway.disconnectCalls, 1);
    expect(
      captureController.state.status,
      BrowserCaptureStatus.reconnectRequired,
    );
    _stage('disconnect-verified');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    _stage('shell-unmounted');
    await mixerController.dispose();
    _stage('mixer-controller-disposed');
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

class _SurfaceMixerController extends BrowserMixerController {
  _SurfaceMixerController() : super(gateway: const _NoopMixerGateway());

  final Set<BrowserMixerStateListener> _surfaceListeners =
      <BrowserMixerStateListener>{};
  BrowserMixerState _surfaceState = const BrowserMixerState.disabled();

  @override
  BrowserMixerState get state => _surfaceState;

  @override
  void addListener(BrowserMixerStateListener listener) {
    _surfaceListeners.add(listener);
  }

  @override
  void removeListener(BrowserMixerStateListener listener) {
    _surfaceListeners.remove(listener);
  }

  @override
  Future<void> attach(String channelId) async {
    _setSurfaceState(
      BrowserMixerState(
        enabled: true,
        activeChannelId: channelId,
        fader: 1,
        muted: false,
        solo: false,
        channelMeter: null,
        masterPeakLeft: 0,
        masterPeakRight: 0,
        limiterActive: false,
      ),
    );
  }

  @override
  Future<void> setFader(double value) async {
    _setSurfaceState(_copyState(fader: value.clamp(0.0, 1.0).toDouble()));
  }

  @override
  Future<void> setMuted(bool value) async {
    _setSurfaceState(_copyState(muted: value));
  }

  @override
  Future<void> setSolo(bool value) async {
    _setSurfaceState(_copyState(solo: value));
  }

  @override
  Future<void> detach() async {
    _setSurfaceState(const BrowserMixerState.disabled());
  }

  void publish(BrowserMixerTelemetry telemetry) {
    final channelId = _surfaceState.activeChannelId;
    if (!_surfaceState.enabled || channelId == null) {
      return;
    }
    _setSurfaceState(
      _copyState(
        channelMeter: telemetry.channelMeters[channelId],
        masterPeakLeft: telemetry.masterPeakLeft,
        masterPeakRight: telemetry.masterPeakRight,
        limiterActive: telemetry.limiterActive,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    _surfaceListeners.clear();
  }

  BrowserMixerState _copyState({
    double? fader,
    bool? muted,
    bool? solo,
    BrowserChannelMeter? channelMeter,
    double? masterPeakLeft,
    double? masterPeakRight,
    bool? limiterActive,
  }) {
    return BrowserMixerState(
      enabled: _surfaceState.enabled,
      activeChannelId: _surfaceState.activeChannelId,
      fader: fader ?? _surfaceState.fader,
      muted: muted ?? _surfaceState.muted,
      solo: solo ?? _surfaceState.solo,
      channelMeter: channelMeter ?? _surfaceState.channelMeter,
      masterPeakLeft: masterPeakLeft ?? _surfaceState.masterPeakLeft,
      masterPeakRight: masterPeakRight ?? _surfaceState.masterPeakRight,
      limiterActive: limiterActive ?? _surfaceState.limiterActive,
    );
  }

  void _setSurfaceState(BrowserMixerState state) {
    _surfaceState = state;
    for (final listener
        in List<BrowserMixerStateListener>.of(_surfaceListeners)) {
      listener(state);
    }
  }
}

class _NoopMixerGateway implements BrowserMixerGateway {
  const _NoopMixerGateway();

  @override
  Stream<BrowserMixerTelemetry> get telemetry =>
      const Stream<BrowserMixerTelemetry>.empty();

  @override
  Future<void> configure(BrowserMixerConfiguration configuration) async {}
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

class _SessionPort implements BrowserSessionPort {
  _SessionPort(TracklistEntry entry)
      : _state = BrowserSessionState(
          initialized: false,
          sessionId: entry.sessionId,
          entries: <TracklistEntry>[entry],
          persistenceStatus: const ServiceStatus.idle(),
        );

  final Set<BrowserSessionStateListener> _listeners =
      <BrowserSessionStateListener>{};
  BrowserSessionState _state;
  final List<String> exportCalls = <String>[];

  @override
  BrowserSessionState get state => _state;

  @override
  void addListener(BrowserSessionStateListener listener) {
    _listeners.add(listener);
  }

  @override
  void removeListener(BrowserSessionStateListener listener) {
    _listeners.remove(listener);
  }

  @override
  Future<void> initialize() async {
    _setState(
      BrowserSessionState(
        initialized: true,
        sessionId: _state.sessionId,
        entries: _state.entries,
        persistenceStatus: _state.persistenceStatus,
      ),
    );
  }

  @override
  Future<bool> recordFingerprintMatch({
    required FingerprintProxyTrack track,
  }) async => false;

  @override
  Future<TracklistEntry> correct({
    required int index,
    required String artist,
    required String title,
  }) async {
    final corrected = _state.entries[index].applyManualCorrection(
      artist: artist,
      title: title,
      correctedAt: DateTime.utc(2026, 9, 11, 11),
    );
    final entries = List<TracklistEntry>.of(_state.entries);
    entries[index] = corrected;
    _setState(
      BrowserSessionState(
        initialized: true,
        sessionId: _state.sessionId,
        entries: entries,
        persistenceStatus: const ServiceStatus.succeeded(),
      ),
    );
    return corrected;
  }

  @override
  Future<void> exportJson() async {
    exportCalls.add('json');
  }

  @override
  Future<void> exportCsv() async {
    exportCalls.add('csv');
  }

  @override
  Future<void> exportM3u() async {
    exportCalls.add('m3u');
  }

  @override
  Future<void> dispose() async {}

  void _setState(BrowserSessionState next) {
    _state = next;
    for (final listener in List<BrowserSessionStateListener>.of(_listeners)) {
      listener(next);
    }
  }
}
