import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/audio_settings_launcher_linux.dart';

void main() {
  test('opens the Linux sound settings panel through GNOME control center', () async {
    final calls = <(String, List<String>)>[];
    final launcher = LinuxAudioSettingsLauncher(
      startProcess: (executable, arguments) async {
        calls.add((executable, arguments));
      },
    );

    await launcher.openAudioInputSettings();

    expect(calls, hasLength(1));
    expect(calls.single.$1, 'xdg-open');
    expect(calls.single.$2, const ['sound']);
  });

  test('surfaces a launcher failure to the recovery UI', () async {
    final launcher = LinuxAudioSettingsLauncher(
      startProcess: (_, __) => Future<void>.error(StateError('not available')),
    );

    await expectLater(
      launcher.openAudioInputSettings(),
      throwsStateError,
    );
  });
}
