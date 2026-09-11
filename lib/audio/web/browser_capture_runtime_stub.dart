import 'browser_capture_controller.dart';
import 'browser_recording_controller.dart';

class BrowserWebRuntime {
  const BrowserWebRuntime({
    required this.captureController,
    required this.recordingController,
  });

  final BrowserCaptureController captureController;
  final BrowserRecordingController recordingController;
}

BrowserWebRuntime createBrowserWebRuntime() {
  return BrowserWebRuntime(
    captureController: BrowserCaptureController(
      gateway: const _UnsupportedBrowserGateway(),
    ),
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
