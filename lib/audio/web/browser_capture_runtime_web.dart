import 'browser_capture_controller.dart';
import 'browser_media_client_web.dart';
import 'browser_media_gateway.dart';

BrowserCaptureController createBrowserCaptureController() {
  final gateway = DefaultBrowserMediaGateway(
    client: WebBrowserMediaClient(),
  );
  return BrowserCaptureController(gateway: gateway);
}
