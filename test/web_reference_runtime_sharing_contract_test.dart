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
      expect(source, contains('MixerDeskView('));
      expect(source, contains('liveState: liveState'));
    });

    test('operator drawer does not allocate a fallback runtime when all audio controllers are injected', () async {
      final source = await File('lib/app/app_surface_web.dart').readAsString();

      expect(
        source,
        isNot(contains('final fallbackRuntime = createBrowserWebRuntime();')),
        reason: 'an unconditional fallback runtime duplicates the injected WebAudio graph',
      );
      expect(source, contains('needsFallbackRuntime'));
      expect(source, contains('if (needsFallbackRuntime)'));
    });

    test('desktop live mode cannot claim unsupported broadcast or loudness telemetry', () async {
      final source = await File('lib/features/mixer/mixer_desk_view.dart').readAsString();

      expect(source, contains('WebReferenceLiveState? liveState'));
      expect(source, contains("'N/A'"));
      expect(source, contains("'UNAVAILABLE'"));
    });
  });
}
