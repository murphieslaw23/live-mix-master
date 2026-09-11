import 'browser_session_controller.dart';
import 'browser_session_tracklist_repository.dart';
import 'browser_tracklist_download_gateway.dart';

BrowserSessionController createBrowserSessionController() {
  return BrowserSessionController(
    repository: BrowserSessionTracklistRepository(),
    downloadGateway: const WebBrowserTracklistDownloadGateway(),
  );
}
