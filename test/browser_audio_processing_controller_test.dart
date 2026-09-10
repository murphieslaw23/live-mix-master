import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/web/browser_audio_processing_controller.dart';
import 'package:live_mix_master/audio/web/browser_capture_controller.dart';

void main() {
  group('BrowserAudioProcessingController', () {
    test('successful AudioWorklet start becomes active for the captured source', () async {
      final gateway = _FakeProcessingGateway();
      final controller = BrowserAudioProcessingController(gateway: gateway);
      const source = BrowserCaptureSource(
        kind: BrowserCaptureKind.microphone,
        id: 'mic-1',
        label: 'USB MIXER',
      );

      await controller.startForSource(source);

      expect(controller.state.status, BrowserAudioProcessingStatus.active);
      expect(controller.state.source?.id, 'mic-1');
      expect(gateway.startedSources, ['mic-1']);
    });

    test('unsupported AudioWorklet path remains explicit', () async {
      final controller = BrowserAudioProcessingController(
        gateway: _FakeProcessingGateway(
          startAttempt: const BrowserAudioProcessingAttempt.unsupported(),
        ),
      );

      await controller.startForSource(
        const BrowserCaptureSource(
          kind: BrowserCaptureKind.displayAudio,
          id: 'display-1',
          label: 'SHARED TAB',
        ),
      );

      expect(controller.state.status, BrowserAudioProcessingStatus.unsupported);
      expect(controller.state.message, contains('AUDIOWORKLET NOT AVAILABLE'));
    });
  });

  group('BrowserAudioRuntimeCoordinator', () {
    test('starts processing on active capture and stops on ended capture', () async {
      final captureGateway = _LifecycleCaptureGateway();
      final capture = BrowserCaptureController(gateway: captureGateway);
      final processingGateway = _FakeProcessingGateway();
      final processing = BrowserAudioProcessingController(gateway: processingGateway);
      final coordinator = BrowserAudioRuntimeCoordinator(
        captureController: capture,
        processingController: processing,
      );

      await capture.requestMicrophone();
      await coordinator.synchronize();

      expect(processing.state.status, BrowserAudioProcessingStatus.active);
      expect(processingGateway.startedSources, ['mic-1']);

      captureGateway.endActiveTrack();
      await coordinator.synchronize();

      expect(processing.state.status, BrowserAudioProcessingStatus.idle);
      expect(processingGateway.stopCount, 1);
    });

    test('device inventory warning does not invent a processing disconnect', () async {
      final captureGateway = _LifecycleCaptureGateway();
      final capture = BrowserCaptureController(gateway: captureGateway);
      final processingGateway = _FakeProcessingGateway();
      final processing = BrowserAudioProcessingController(gateway: processingGateway);
      final coordinator = BrowserAudioRuntimeCoordinator(
        captureController: capture,
        processingController: processing,
      );

      await capture.requestMicrophone();
      await coordinator.synchronize();
      captureGateway.changeDeviceInventory();
      await coordinator.synchronize();

      expect(processing.state.status, BrowserAudioProcessingStatus.active);
      expect(processingGateway.stopCount, 0);
    });
  });
}

class _FakeProcessingGateway implements BrowserAudioProcessingGateway {
  _FakeProcessingGateway({
    this.startAttempt = const BrowserAudioProcessingAttempt.started(),
  });

  final BrowserAudioProcessingAttempt startAttempt;
  final List<String> startedSources = <String>[];
  int stopCount = 0;

  @override
  Future<BrowserAudioProcessingAttempt> start(BrowserCaptureSource source) async {
    startedSources.add(source.id);
    return startAttempt;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }
}

class _LifecycleCaptureGateway
    implements BrowserMediaGateway, BrowserMediaLifecycleGateway {
  void Function()? _onEnded;
  void Function()? _onDeviceChange;

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
        id: 'mic-1',
        label: 'USB MIXER',
      ),
    );
  }

  @override
  Future<BrowserCaptureAttempt> requestDisplayAudio() async {
    return const BrowserCaptureAttempt.unsupported();
  }

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
