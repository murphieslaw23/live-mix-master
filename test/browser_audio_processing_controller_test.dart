import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/web/browser_audio_processing_controller.dart';
import 'package:live_mix_master/audio/web/browser_capture_controller.dart';
import 'package:live_mix_master/audio/web/browser_mixer_controller.dart';
import 'package:live_mix_master/audio/web/browser_mixer_protocol.dart';

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
    test('active processing attaches mixer and ended capture detaches it', () async {
      final captureGateway = _LifecycleCaptureGateway();
      final capture = BrowserCaptureController(gateway: captureGateway);
      final processingGateway = _FakeProcessingGateway();
      final processing = BrowserAudioProcessingController(gateway: processingGateway);
      final mixerGateway = _FakeMixerGateway();
      final mixer = BrowserMixerController(gateway: mixerGateway);
      final coordinator = BrowserAudioRuntimeCoordinator(
        captureController: capture,
        processingController: processing,
        mixerController: mixer,
      );

      await capture.requestMicrophone();
      await coordinator.synchronize();

      expect(processing.state.status, BrowserAudioProcessingStatus.active);
      expect(processingGateway.startedSources, ['mic-1']);
      expect(mixer.state.enabled, isTrue);
      expect(mixer.state.activeChannelId, 'mic-1');
      expect(mixerGateway.configurations.single.channels.single.id, 'mic-1');

      captureGateway.endActiveTrack();
      await coordinator.synchronize();

      expect(processing.state.status, BrowserAudioProcessingStatus.idle);
      expect(processingGateway.stopCount, 1);
      expect(mixer.state.enabled, isFalse);

      await coordinator.dispose();
      await mixer.dispose();
      await mixerGateway.dispose();
    });

    test('device inventory warning keeps processing and mixer attached', () async {
      final captureGateway = _LifecycleCaptureGateway();
      final capture = BrowserCaptureController(gateway: captureGateway);
      final processingGateway = _FakeProcessingGateway();
      final processing = BrowserAudioProcessingController(gateway: processingGateway);
      final mixerGateway = _FakeMixerGateway();
      final mixer = BrowserMixerController(gateway: mixerGateway);
      final coordinator = BrowserAudioRuntimeCoordinator(
        captureController: capture,
        processingController: processing,
        mixerController: mixer,
      );

      await capture.requestMicrophone();
      await coordinator.synchronize();
      captureGateway.changeDeviceInventory();
      await coordinator.synchronize();

      expect(processing.state.status, BrowserAudioProcessingStatus.active);
      expect(processingGateway.stopCount, 0);
      expect(mixer.state.enabled, isTrue);
      expect(mixer.state.activeChannelId, 'mic-1');

      await coordinator.dispose();
      await mixer.dispose();
      await mixerGateway.dispose();
    });

    test('failed processing never attaches the mixer', () async {
      final captureGateway = _LifecycleCaptureGateway();
      final capture = BrowserCaptureController(gateway: captureGateway);
      final processing = BrowserAudioProcessingController(
        gateway: _FakeProcessingGateway(
          startAttempt: const BrowserAudioProcessingAttempt.failed('START FAILED'),
        ),
      );
      final mixerGateway = _FakeMixerGateway();
      final mixer = BrowserMixerController(gateway: mixerGateway);
      final coordinator = BrowserAudioRuntimeCoordinator(
        captureController: capture,
        processingController: processing,
        mixerController: mixer,
      );

      await capture.requestMicrophone();
      await coordinator.synchronize();

      expect(processing.state.status, BrowserAudioProcessingStatus.error);
      expect(mixer.state.enabled, isFalse);
      expect(mixerGateway.configurations, isEmpty);

      await coordinator.dispose();
      await mixer.dispose();
      await mixerGateway.dispose();
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

class _FakeMixerGateway implements BrowserMixerGateway {
  final StreamController<BrowserMixerTelemetry> _telemetry =
      StreamController<BrowserMixerTelemetry>.broadcast();
  final List<BrowserMixerConfiguration> configurations =
      <BrowserMixerConfiguration>[];

  @override
  Stream<BrowserMixerTelemetry> get telemetry => _telemetry.stream;

  @override
  Future<void> configure(BrowserMixerConfiguration configuration) async {
    configurations.add(configuration);
  }

  Future<void> dispose() => _telemetry.close();
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
