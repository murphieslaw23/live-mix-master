import 'browser_capture_controller.dart';

BrowserCaptureController createBrowserCaptureController() {
  return BrowserCaptureController(gateway: const _UnsupportedBrowserGateway());
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
