import '../../services/web/browser_fingerprint_lookup_controller.dart';
import 'browser_audio_processing_controller.dart';
import 'browser_audio_worklet_gateway_web.dart';
import 'browser_capture_controller.dart';
import 'browser_media_client_web.dart';
import 'browser_media_gateway.dart';
import 'browser_mixer_controller.dart';
import 'browser_recording_controller.dart';

class BrowserWebRuntime {
  const BrowserWebRuntime({
    required this.captureController,
    required this.processingController,
    required this.mixerController,
    required this.recordingController,
    required this.fingerprintController,
  });

  final BrowserCaptureController captureController;
  final BrowserAudioProcessingController processingController;
  final BrowserMixerController mixerController;
  final BrowserRecordingController recordingController;
  final BrowserFingerprintLookupController fingerprintController;
}

BrowserWebRuntime createBrowserWebRuntime({
  BrowserFingerprintLookupController? fingerprintController,
}) {
  final resolvedFingerprintController =
      fingerprintController ?? BrowserFingerprintLookupController();
  final client = WebBrowserMediaClient();
  final mediaGateway = DefaultBrowserMediaGateway(client: client);
  final captureController = BrowserCaptureController(gateway: mediaGateway);
  final audioGateway = WebAudioWorkletGateway(
    activeStream: () => client.activeStream,
    preparedFingerprintHandler: ({
      required String fingerprint,
      required int durationSeconds,
    }) {
      return resolvedFingerprintController.lookupPreparedFingerprint(
        fingerprint: fingerprint,
        durationSeconds: durationSeconds,
      );
    },
  );
  final processingController = BrowserAudioProcessingController(
    gateway: audioGateway,
  );
  final mixerController = BrowserMixerController(
    gateway: audioGateway,
  );
  final recordingController = BrowserRecordingController(
    gateway: audioGateway,
  );

  BrowserAudioRuntimeCoordinator(
    captureController: captureController,
    processingController: processingController,
    mixerController: mixerController,
  );

  return BrowserWebRuntime(
    captureController: captureController,
    processingController: processingController,
    mixerController: mixerController,
    recordingController: recordingController,
    fingerprintController: resolvedFingerprintController,
  );
}

BrowserCaptureController createBrowserCaptureController() {
  return createBrowserWebRuntime().captureController;
}

BrowserRecordingController createBrowserRecordingController() {
  return createBrowserWebRuntime().recordingController;
}
