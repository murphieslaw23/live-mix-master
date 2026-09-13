import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop surface wires microphone settings launcher into mixer recovery', () {
    final source = File('lib/app/app_surface_desktop.dart').readAsStringSync();

    expect(source, contains("../audio/macos_audio_settings_launcher.dart"));
    expect(source, contains('MacosAudioSettingsLauncher'));
    expect(source, contains('onOpenAudioSettings:'));
    expect(source, contains('.openMicrophonePrivacy'));
  });
}
