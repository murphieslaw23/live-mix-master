import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/web/browser_capture_controller.dart';

void main() {
  group('BrowserCaptureController', () {
    test('probe reports explicit browser capability boundaries', () async {
      final gateway = _FakeGateway(
        capabilities: const BrowserAudioCapabilities(
          mediaDevicesAvailable: true,
          microphoneCaptureAvailable: true,
          displayCaptureAvailable: true,
          systemAudioGuaranteed: false,
        ),
      );
      final controller = BrowserCaptureController(gateway: gateway);

      await controller.probe();

      expect(controller.state.status, BrowserCaptureStatus.permissionRequired);
      expect(controller.state.capabilities?.microphoneCaptureAvailable, isTrue);
      expect(controller.state.capabilities?.displayCaptureAvailable, isTrue);
      expect(controller.state.capabilities?.systemAudioGuaranteed, isFalse);
    });

    test('microphone permission success activates an audio source', () async {
      final gateway = _FakeGateway(
        microphoneAttempt: BrowserCaptureAttempt.connected(
          const BrowserCaptureSource(
            kind: BrowserCaptureKind.microphone,
            id: 'origin-scoped-device',
            label: 'USB AUDIO',
          ),
        ),
      );
      final controller = BrowserCaptureController(gateway: gateway);

      await controller.requestMicrophone();

      expect(controller.state.status, BrowserCaptureStatus.active);
      expect(controller.state.source?.kind, BrowserCaptureKind.microphone);
      expect(controller.state.source?.label, 'USB AUDIO');
    });

    test('permission denial is an actionable state', () async {
      final gateway = _FakeGateway(
        microphoneAttempt: const BrowserCaptureAttempt.permissionDenied(),
      );
      final controller = BrowserCaptureController(gateway: gateway);

      await controller.requestMicrophone();

      expect(controller.state.status, BrowserCaptureStatus.permissionDenied);
      expect(controller.state.message, contains('PERMISSION DENIED'));
    });

    test('display capture without an audio track never becomes active', () async {
      final gateway = _FakeGateway(
        displayAttempt: const BrowserCaptureAttempt.noAudioTrack(),
      );
      final controller = BrowserCaptureController(gateway: gateway);

      await controller.requestDisplayAudio();

      expect(controller.state.status, BrowserCaptureStatus.noAudioTrack);
      expect(controller.state.source, isNull);
      expect(controller.state.message, contains('NO AUDIO TRACK RETURNED'));
    });

    test('unsupported display capture is explicit', () async {
      final gateway = _FakeGateway(
        displayAttempt: const BrowserCaptureAttempt.unsupported(),
      );
      final controller = BrowserCaptureController(gateway: gateway);

      await controller.requestDisplayAudio();

      expect(controller.state.status, BrowserCaptureStatus.unsupported);
      expect(controller.state.message, contains('NOT EXPOSED'));
    });

    test('ended media track requires reconnect and clears the source', () async {
      final gateway = _FakeGateway(
        microphoneAttempt: BrowserCaptureAttempt.connected(
          const BrowserCaptureSource(
            kind: BrowserCaptureKind.microphone,
            id: 'origin-scoped-device',
            label: 'USB AUDIO',
          ),
        ),
      );
      final controller = BrowserCaptureController(gateway: gateway);
      await controller.requestMicrophone();

      controller.handleTrackEnded();

      expect(controller.state.status, BrowserCaptureStatus.reconnectRequired);
      expect(controller.state.source, isNull);
      expect(controller.state.message, contains('CAPTURE ENDED'));
    });
  });
}

class _FakeGateway implements BrowserMediaGateway {
  _FakeGateway({
    this.capabilities = const BrowserAudioCapabilities(
      mediaDevicesAvailable: true,
      microphoneCaptureAvailable: true,
      displayCaptureAvailable: true,
      systemAudioGuaranteed: false,
    ),
    this.microphoneAttempt = const BrowserCaptureAttempt.unsupported(),
    this.displayAttempt = const BrowserCaptureAttempt.unsupported(),
  });

  final BrowserAudioCapabilities capabilities;
  final BrowserCaptureAttempt microphoneAttempt;
  final BrowserCaptureAttempt displayAttempt;

  @override
  Future<BrowserAudioCapabilities> probeCapabilities() async => capabilities;

  @override
  Future<BrowserCaptureAttempt> requestMicrophone() async => microphoneAttempt;

  @override
  Future<BrowserCaptureAttempt> requestDisplayAudio() async => displayAttempt;
}
