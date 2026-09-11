import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/app/app_surface_web.dart';
import 'package:live_mix_master/audio/web/browser_capture_controller.dart';
import 'package:live_mix_master/services/web/browser_fingerprint_lookup_controller.dart';
import 'package:live_mix_master/services/web/fingerprint_proxy_client.dart';
import 'package:live_mix_master/services/web/browser_session_controller.dart';
import 'package:live_mix_master/services/reliability_models.dart';
import 'package:live_mix_master/services/session_tracklist_repository.dart';

void main() {
  group('BrowserFingerprintLookupController', () {
    test('maps match and no-match into deterministic operator states', () async {
      final gateway = _QueueFingerprintGateway([
        const FingerprintProxyResult.matched(
          FingerprintProxyTrack(
            artist: 'System Corrupt',
            title: 'Signal Ritual',
            release: null,
            providerId: 'acoustid-1',
            confidence: 0.93,
          ),
        ),
        const FingerprintProxyResult.noMatch(),
      ]);
      final controller = BrowserFingerprintLookupController(gateway: gateway);

      await controller.lookupPreparedFingerprint(
        fingerprint: 'prepared-1',
        durationSeconds: 10,
      );
      expect(controller.state.status, BrowserFingerprintLookupStatus.matched);
      expect(
        controller.state.message,
        'TRACK MATCH — SYSTEM CORRUPT — SIGNAL RITUAL — 93%',
      );

      await controller.lookupPreparedFingerprint(
        fingerprint: 'prepared-2',
        durationSeconds: 10,
      );
      expect(controller.state.status, BrowserFingerprintLookupStatus.noMatch);
      expect(controller.state.message, 'NO CONFIDENT TRACK MATCH — SESSION CONTINUES');
    });

    test('maps provider failure code to fixed safe operator copy and notifies listeners', () async {
      final gateway = _QueueFingerprintGateway([
        const FingerprintProxyResult.failed(
          failureCode: FingerprintProxyFailureCode.rateLimited,
          message: 'arbitrary server wording must not become operator copy',
        ),
      ]);
      final controller = BrowserFingerprintLookupController(gateway: gateway);
      final states = <BrowserFingerprintLookupStatus>[];
      controller.addListener((state) => states.add(state.status));

      await controller.lookupPreparedFingerprint(
        fingerprint: 'prepared',
        durationSeconds: 10,
      );

      expect(states, [
        BrowserFingerprintLookupStatus.lookingUp,
        BrowserFingerprintLookupStatus.failed,
      ]);
      expect(controller.state.failureCode, FingerprintProxyFailureCode.rateLimited);
      expect(
        controller.state.message,
        'FINGERPRINT PROVIDER RATE LIMITED — RETRY LATER',
      );
      expect(controller.state.message, isNot(contains('arbitrary server wording')));
    });
  });


  test('maps a preparation failure to explicit safe operator copy', () {
    final controller = BrowserFingerprintLookupController(gateway: _QueueFingerprintGateway([]));

    controller.reportPreparationUnavailable();

    expect(controller.state.status, BrowserFingerprintLookupStatus.failed);
    expect(controller.state.failureCode, FingerprintProxyFailureCode.unavailable);
    expect(
      controller.state.message,
      'FINGERPRINT PREPARATION UNAVAILABLE — MIX / RECORDING CONTINUE',
    );
  });



  testWidgets('WebReleaseShell persists a matched fingerprint into the session tracklist', (tester) async {
    final repository = _SessionRepository();
    final sessionController = BrowserSessionController(
      repository: repository,
      downloadGateway: const _NoopDownloadGateway(),
      createSessionId: () => 'web-session',
      clock: () => DateTime.utc(2026, 9, 11, 12),
    );
    final fingerprintController = BrowserFingerprintLookupController(
      gateway: _QueueFingerprintGateway([
        const FingerprintProxyResult.matched(
          FingerprintProxyTrack(
            artist: 'System Corrupt',
            title: 'Signal Ritual',
            release: null,
            providerId: 'acoustid-1',
            confidence: 0.93,
          ),
        ),
      ]),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WebReleaseShell(
          controller: BrowserCaptureController(gateway: _CaptureGateway()),
          fingerprintController: fingerprintController,
          sessionController: sessionController,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await fingerprintController.lookupPreparedFingerprint(
      fingerprint: 'prepared',
      durationSeconds: 10,
    );
    await tester.pumpAndSettle();

    expect(sessionController.entries, hasLength(1));
    expect(sessionController.entries.single.title, 'Signal Ritual');
    expect(sessionController.entries.single.provenance, TrackProvenance.automatic);
    expect(repository.savedSnapshots, hasLength(1));

    await sessionController.dispose();
  });

  testWidgets('WebReleaseShell visibly reacts to asynchronous provider failure', (tester) async {
    final fingerprintController = BrowserFingerprintLookupController(
      gateway: _QueueFingerprintGateway([
        const FingerprintProxyResult.failed(
          failureCode: FingerprintProxyFailureCode.unavailable,
          message: 'internal provider detail',
        ),
      ]),
    );
    final captureController = BrowserCaptureController(gateway: _CaptureGateway());

    await tester.pumpWidget(
      MaterialApp(
        home: WebReleaseShell(
          controller: captureController,
          fingerprintController: fingerprintController,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('FINGERPRINT PROXY READY — AWAITING PREPARED FINGERPRINT'),
      findsOneWidget,
    );

    await fingerprintController.lookupPreparedFingerprint(
      fingerprint: 'prepared',
      durationSeconds: 10,
    );
    await tester.pump();

    expect(
      find.text('FINGERPRINT PROVIDER UNAVAILABLE — MIX / RECORDING CONTINUE'),
      findsOneWidget,
    );
    expect(find.textContaining('internal provider detail'), findsNothing);
  });
}



class _SessionRepository implements SessionTracklistRepository {
  final StreamController<ServiceStatus> _statuses =
      StreamController<ServiceStatus>.broadcast();
  final List<List<TracklistEntry>> savedSnapshots = <List<TracklistEntry>>[];

  @override
  Stream<ServiceStatus> get onStatus => _statuses.stream;

  @override
  Future<List<TracklistEntry>> load() async => const <TracklistEntry>[];

  @override
  Future<void> save(Iterable<TracklistEntry> entries) async {
    savedSnapshots.add(List<TracklistEntry>.unmodifiable(entries));
  }

  @override
  Future<void> dispose() => _statuses.close();
}

class _NoopDownloadGateway implements BrowserTracklistDownloadGateway {
  const _NoopDownloadGateway();

  @override
  Future<void> download({
    required String fileName,
    required String mimeType,
    required String contents,
  }) async {}
}

class _QueueFingerprintGateway implements BrowserFingerprintLookupGateway {
  _QueueFingerprintGateway(this.results);

  final List<FingerprintProxyResult> results;
  var index = 0;

  @override
  Future<FingerprintProxyResult> lookup({
    required String fingerprint,
    required int durationSeconds,
    double minimumConfidence = 0.65,
  }) async {
    return results[index++];
  }
}

class _CaptureGateway implements BrowserMediaGateway {
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
