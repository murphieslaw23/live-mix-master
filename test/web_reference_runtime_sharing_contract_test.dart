import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('web reference shared-runtime contract', () {
    test('reference shell owns one browser runtime and injects it into operator drawer', () async {
      final source = await File('lib/app/app_surface_web_reference.dart').readAsString();

      expect(source, contains('class WebReferenceSurface extends StatefulWidget'));
      expect(source, contains('createBrowserWebRuntime()'));
      expect(source, contains('controller: _runtime.captureController'));
      expect(source, contains('recordingController: _runtime.recordingController'));
      expect(source, contains('fingerprintController: _runtime.fingerprintController'));
      expect(source, contains('mixerController: _runtime.mixerController'));
      expect(source, isNot(contains('child: const WebReleaseShell()')));
    });

    test('reference shell feeds verified live state into compact and desktop surfaces', () async {
      final source = await File('lib/app/app_surface_web_reference.dart').readAsString();

      expect(source, contains('WebReferenceLiveState.fromBrowserStates'));
      expect(source, contains('CompactMonitorView('));
      expect(source, contains('currentTrackTitle: liveState.currentTrackTitle'));
      expect(source, contains('masterPeakLevel: liveState.masterPeakLevel'));
      expect(source, contains('WebLiveMixerReference('));
      expect(source, contains('liveState: liveState'));
    });

    test('Web runtime factory reuses the same AudioWorklet graph on browser builds', () async {
      final source = await File('lib/audio/web/browser_capture_runtime_web.dart').readAsString();

      expect(source, contains('BrowserWebRuntime? _sharedBrowserWebRuntime'));
      expect(source, contains('if (_sharedBrowserWebRuntime case final runtime?)'));
      expect(source, contains('_sharedBrowserWebRuntime = runtime'));
    });

    test('desktop live reference cannot claim unsupported broadcast or loudness telemetry', () async {
      final source = await File('lib/app/web_live_mixer_reference.dart').readAsString();

      expect(source, contains("'N/A'"));
      expect(source, contains("'UNAVAILABLE'"));
      expect(source, isNot(contains('-14.2 LUFS')));
      expect(source, isNot(contains('-6.0 dBTP')));
      expect(source, isNot(contains('PREFLIGHT OK')));
      expect(source, isNot(contains('320 KBPS')));
    });
  });
}
