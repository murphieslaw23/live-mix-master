import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('browser session repository uses namespaced localStorage plus shared codec', () {
    final source = File(
      'lib/services/web/browser_session_tracklist_repository.dart',
    ).readAsStringSync();

    expect(source, contains("'lmm.session.active'"));
    expect(source, contains('SessionTracklistCodec'));
    expect(source, contains('localStorage.getItem'));
    expect(source, contains('localStorage.setItem'));
    expect(source, contains('ServiceFailureCode.malformedResponse'));
    expect(source, contains('ServiceFailureCode.writeFailed'));
    expect(source, isNot(contains('dart:io')));
    expect(source, isNot(contains('session_tracklist_store.dart')));
  });

  test('browser download adapter creates and revokes object URLs', () {
    final source = File(
      'lib/services/web/browser_tracklist_download_gateway.dart',
    ).readAsStringSync();

    expect(source, contains('web.Blob('));
    expect(source, contains('web.BlobPropertyBag(type: mimeType)'));
    expect(source, contains('web.URL.createObjectURL'));
    expect(source, contains('anchor.click()'));
    expect(source, contains('web.URL.revokeObjectURL'));
    expect(source, isNot(contains('dart:io')));
  });
}
