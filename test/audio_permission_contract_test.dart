import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('macOS audio permission packaging contract', () {
    test('Info.plist explains microphone access to the operator', () {
      final info = File('macos/Runner/Info.plist').readAsStringSync();

      expect(info, contains('<key>NSMicrophoneUsageDescription</key>'));
      final usageDescription = RegExp(
        r'<key>NSMicrophoneUsageDescription</key>\s*<string>([^<]+)</string>',
      ).firstMatch(info)?.group(1);
      expect(usageDescription, isNotNull);
      expect(usageDescription!.trim().length, greaterThanOrEqualTo(20));
      expect(usageDescription.toLowerCase(), contains('audio'));
    });

    test('sandboxed debug and release builds allow microphone input', () {
      for (final path in <String>[
        'macos/Runner/DebugProfile.entitlements',
        'macos/Runner/Release.entitlements',
      ]) {
        final entitlements = File(path).readAsStringSync();
        expect(
          entitlements,
          contains('<key>com.apple.security.device.microphone</key>'),
          reason: '$path must opt in to App Sandbox microphone access',
        );
        expect(
          RegExp(
            r'<key>com\.apple\.security\.device\.microphone</key>\s*<true\s*/>',
          ).hasMatch(entitlements),
          isTrue,
          reason: '$path must enable the microphone entitlement',
        );
      }
    });
  });
}
