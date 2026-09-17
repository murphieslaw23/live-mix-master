import 'dart:io';

import 'audio_settings_launcher_port.dart';

typedef MacosProcessRunner = Future<int> Function(
  String executable,
  List<String> arguments,
);

/// Opens the macOS microphone privacy pane from the non-real-time host side.
class MacosAudioSettingsLauncher implements AudioSettingsLauncher {
  MacosAudioSettingsLauncher({MacosProcessRunner? runProcess})
      : runProcess = runProcess ?? _run;

  final MacosProcessRunner runProcess;

  static Future<int> _run(
    String executable,
    List<String> arguments,
  ) async {
    final result = await Process.run(executable, arguments);
    return result.exitCode;
  }

  @override
  Future<void> openAudioInputSettings() => openMicrophonePrivacy();

  Future<void> openMicrophonePrivacy() async {
    final exitCode = await runProcess(
      'open',
      const [
        'x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone',
      ],
    );
    if (exitCode != 0) {
      throw StateError('Unable to open macOS microphone settings.');
    }
  }
}
