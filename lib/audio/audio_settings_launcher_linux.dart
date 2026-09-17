import 'dart:io';

import 'audio_settings_launcher_port.dart';

typedef LinuxProcessStarter = Future<void> Function(
  String executable,
  List<String> arguments,
);

/// Opens the GNOME-compatible system sound panel from the non-real-time host.
class LinuxAudioSettingsLauncher implements AudioSettingsLauncher {
  LinuxAudioSettingsLauncher({LinuxProcessStarter? startProcess})
      : startProcess = startProcess ?? _start;

  final LinuxProcessStarter startProcess;

  static Future<void> _start(
    String executable,
    List<String> arguments,
  ) async {
    try {
      await Process.start(
        executable,
        arguments,
        mode: ProcessStartMode.detached,
      );
    } on ProcessException catch (error) {
      throw StateError('Unable to open Linux sound settings: ${error.message}');
    }
  }

  @override
  Future<void> openAudioInputSettings() =>
      startProcess('gnome-control-center', const ['sound']);
}
