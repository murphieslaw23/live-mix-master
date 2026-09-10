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

    test('listeners receive asynchronous lifecycle state changes', () async {
      final gateway = _LifecycleGateway(
        microphoneAttempt: const BrowserCaptureAttempt.connected(
          BrowserCaptureSource(
            kind: BrowserCaptureKind.microphone,
            id: 'origin-scoped-device',
            label: 'USB AUDIO',
          ),
        ),
      );
      final controller = BrowserCaptureController(gateway: gateway);
      final statuses = <BrowserCaptureStatus>[];
      controller.addListener((state) => statuses.add(state.status));

      await controller.requestMicrophone();
      gateway.endActiveTrack();

      expect(statuses, contains(BrowserCaptureStatus.active));
      expect(statuses.last, BrowserCaptureStatus.reconnectRequired);
    });

    test('device inventory changes are explicit without inventing disconnect', () async {
      final gateway = _LifecycleGateway(
        microphoneAttempt: const BrowserCaptureAttempt.connected(
          BrowserCaptureSource(
            kind: BrowserCaptureKind.microphone,
            id: 'origin-scoped-device',
            label: 'USB AUDIO',
          ),
        ),
      );
      final controller = BrowserCaptureController(gateway: gateway);
      await controller.requestMicrophone();

      gateway.changeDeviceInventory();

      expect(controller.state.status, BrowserCaptureStatus.deviceInventoryChanged);
      expect(controller.state.source?.label, 'USB AUDIO');
      expect(controller.state.message, contains('DEVICE LIST CHANGED'));
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

class _LifecycleGateway extends _FakeGateway implements BrowserMediaLifecycleGateway {
  _LifecycleGateway({
    super.capabilities,
    super.microphoneAttempt,
    super.displayAttempt,
  });

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
