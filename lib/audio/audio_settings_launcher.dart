import 'dart:io';

import 'audio_settings_launcher_port.dart';
import 'audio_settings_launcher_linux.dart';
import 'macos_audio_settings_launcher.dart';

export 'audio_settings_launcher_port.dart';

AudioSettingsLauncher createDesktopAudioSettingsLauncher() {
  if (Platform.isMacOS) return MacosAudioSettingsLauncher();
  if (Platform.isLinux) return LinuxAudioSettingsLauncher();
  return const _UnsupportedAudioSettingsLauncher();
}

class _UnsupportedAudioSettingsLauncher implements AudioSettingsLauncher {
  const _UnsupportedAudioSettingsLauncher();

  @override
  Future<void> openAudioInputSettings() {
    return Future<void>.error(
      UnsupportedError('Audio settings recovery is unavailable on this platform.'),
    );
  }
}
