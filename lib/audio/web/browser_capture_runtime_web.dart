import 'browser_audio_processing_controller.dart';
import 'browser_audio_worklet_gateway_web.dart';
import 'browser_capture_controller.dart';
import 'browser_media_client_web.dart';
import 'browser_media_gateway.dart';

BrowserCaptureController createBrowserCaptureController() {
  final client = WebBrowserMediaClient();
  final gateway = DefaultBrowserMediaGateway(client: client);
  final captureController = BrowserCaptureController(gateway: gateway);
  final processingController = BrowserAudioProcessingController(
    gateway: WebAudioWorkletGateway(
      activeStream: () => client.activeStream,
    ),
  );

  BrowserAudioRuntimeCoordinator(
    captureController: captureController,
    processingController: processingController,
  );

  return captureController;
}
