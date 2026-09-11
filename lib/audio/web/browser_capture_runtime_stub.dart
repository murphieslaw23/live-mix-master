import 'dart:async';

import 'browser_audio_processing_controller.dart';
import 'browser_capture_controller.dart';
import 'browser_mixer_controller.dart';
import 'browser_mixer_protocol.dart';
import 'browser_recording_controller.dart';

class BrowserWebRuntime {
  const BrowserWebRuntime({
    required this.captureController,
    required this.processingController,
    required this.mixerController,
    required this.recordingController,
  });

  final BrowserCaptureController captureController;
  final BrowserAudioProcessingController processingController;
  final BrowserMixerController mixerController;
  final BrowserRecordingController recordingController;
}

BrowserWebRuntime createBrowserWebRuntime() {
  final mixerController = BrowserMixerController(
    gateway: const _UnsupportedBrowserMixerGateway(),
  );
  return BrowserWebRuntime(
    captureController: BrowserCaptureController(
      gateway: const _UnsupportedBrowserGateway(),
    ),
    processingController: BrowserAudioProcessingController(
      gateway: const _UnsupportedBrowserProcessingGateway(),
    ),
    mixerController: mixerController,
    recordingController: BrowserRecordingController(
      gateway: const _UnsupportedBrowserRecordingGateway(),
    ),
  );
}

BrowserCaptureController createBrowserCaptureController() {
  return createBrowserWebRuntime().captureController;
}

BrowserRecordingController createBrowserRecordingController() {
  return createBrowserWebRuntime().recordingController;
}

class _UnsupportedBrowserGateway implements BrowserMediaGateway {
  const _UnsupportedBrowserGateway();

  @override
  Future<BrowserAudioCapabilities> probeCapabilities() async {
    return const BrowserAudioCapabilities(
      mediaDevicesAvailable: false,
      microphoneCaptureAvailable: false,
      displayCaptureAvailable: false,
      systemAudioGuaranteed: false,
    );
  }

  @override
  Future<BrowserCaptureAttempt> requestMicrophone() async {
    return const BrowserCaptureAttempt.unsupported();
  }

  @override
  Future<BrowserCaptureAttempt> requestDisplayAudio() async {
    return const BrowserCaptureAttempt.unsupported();
  }
}

class _UnsupportedBrowserProcessingGateway
    implements BrowserAudioProcessingGateway {
  const _UnsupportedBrowserProcessingGateway();

  @override
  Future<BrowserAudioProcessingAttempt> start(BrowserCaptureSource source) async {
    return const BrowserAudioProcessingAttempt.unsupported();
  }

  @override
  Future<void> stop() async {}
}

class _UnsupportedBrowserMixerGateway implements BrowserMixerGateway {
  const _UnsupportedBrowserMixerGateway();

  @override
  Stream<BrowserMixerTelemetry> get telemetry =>
      const Stream<BrowserMixerTelemetry>.empty();

  @override
  Future<void> configure(BrowserMixerConfiguration configuration) async {
    throw StateError('MIXER CONFIGURATION UNAVAILABLE — AUDIOWORKLET NOT ACTIVE');
  }
}

class _UnsupportedBrowserRecordingGateway implements BrowserRecordingGateway {
  const _UnsupportedBrowserRecordingGateway();

  @override
  Future<void> startRecording() async {
    throw const BrowserRecordingException(
      BrowserRecordingFailure.notReady,
      'RECORDING UNAVAILABLE — AUDIOWORKLET NOT ACTIVE',
    );
  }

  @override
  Future<BrowserRecordingArtifact> stopRecording() async {
    throw const BrowserRecordingException(
      BrowserRecordingFailure.notReady,
      'RECORDING STOP FAILED — RECORDING NOT ACTIVE',
    );
  }

  @override
  Future<void> exportRecording(BrowserRecordingArtifact artifact) async {
    throw const BrowserRecordingException(
      BrowserRecordingFailure.exportFailed,
      'WAV EXPORT UNAVAILABLE — NO FINALIZED RECORDING',
    );
  }
}
