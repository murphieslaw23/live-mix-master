import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'browser_session_controller.dart';

class WebBrowserTracklistDownloadGateway
    implements BrowserTracklistDownloadGateway {
  const WebBrowserTracklistDownloadGateway();

  @override
  Future<void> download({
    required String fileName,
    required String mimeType,
    required String contents,
  }) async {
    final blob = web.Blob(
      <JSString>[contents.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    final objectUrl = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = objectUrl
      ..download = fileName;
    web.document.body?.appendChild(anchor);
    try {
      anchor.click();
    } finally {
      anchor.remove();
      web.URL.revokeObjectURL(objectUrl);
    }
  }
}
