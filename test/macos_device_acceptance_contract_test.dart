import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Issue #3 macOS device acceptance package', () {
    test('documents the real physical and BlackHole-compatible E2E procedure', () {
      final e2e = File('docs/audio/macos-device-e2e.md');
      expect(e2e.existsSync(), isTrue);

      final content = e2e.readAsStringSync();
      for (final required in <String>[
        'physical input',
        'BlackHole',
        'stable UID',
        '10 seconds',
        'callback count',
        'xrun',
        'overflow',
        'disconnect',
        'reconnect',
      ]) {
        expect(
          content.toLowerCase(),
          contains(required.toLowerCase()),
          reason: 'macOS device E2E guide must include "$required"',
        );
      }
    });

    test('keeps a non-secret acceptance record with an explicit pending gate', () {
      final record = File('docs/audio/issue3-device-acceptance-record.md');
      expect(record.existsSync(), isTrue);

      final content = record.readAsStringSync();
      for (final required in <String>[
        'PENDING REAL DEVICE RUN',
        'PR head SHA',
        'macOS version',
        'endpoint UID',
        'sample rate',
        'buffer frames',
        'input channels',
        'average callback',
        'maximum callback',
        'callback count',
        'xrun count',
        'recorder rejected blocks',
        'fingerprint rejected blocks',
        'recording duration',
        'disconnect/reconnect',
      ]) {
        expect(
          content,
          contains(required),
          reason: 'acceptance record must include "$required"',
        );
      }
    });

    test('records DSP and callback safety evidence without claiming device E2E', () {
      final safety = File('docs/audio/dsp-safety-evidence.md');
      expect(safety.existsSync(), isTrue);

      final content = safety.readAsStringSync();
      for (final required in <String>[
        'no heap allocation',
        'no mutex',
        'no disk I/O',
        'no network I/O',
        'no logging',
        'no Dart',
        'SPSC',
        'limiter',
        'does not satisfy',
      ]) {
        expect(
          content.toLowerCase(),
          contains(required.toLowerCase()),
          reason: 'DSP safety evidence must include "$required"',
        );
      }
    });

    test('builds a native macOS probe around the production ABI', () {
      final source = File('native/tools/macos_device_probe.cpp');
      expect(source.existsSync(), isTrue);

      final sourceContent = source.readAsStringSync();
      for (final symbol in <String>[
        'lmm_list_input_devices',
        'lmm_capture_start',
        'lmm_capture_get_status',
        'lmm_get_pcm_handoff_status',
      ]) {
        expect(sourceContent, contains(symbol));
      }

      final cmake = File('native/CMakeLists.txt').readAsStringSync();
      expect(cmake, contains('macos_device_probe'));
      expect(cmake, contains('tools/macos_device_probe.cpp'));
    });

    test('top-level development docs link the device acceptance guide', () {
      for (final path in <String>['README.md', 'DEVELOPMENT.md']) {
        final content = File(path).readAsStringSync();
        expect(
          content,
          contains('docs/audio/macos-device-e2e.md'),
          reason: '$path must link the macOS device E2E guide',
        );
      }
    });
  });
}
