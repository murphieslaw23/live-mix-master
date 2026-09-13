import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/macos_audio_settings_launcher.dart';

void main() {
  test('opens macOS microphone privacy settings', () async {
    final calls = <(String, List<String>)>[];
    final launcher = MacosAudioSettingsLauncher(
      runProcess: (executable, args) async {
        calls.add((executable, args));
        return 0;
      },
    );

    await launcher.openMicrophonePrivacy();

    expect(calls, hasLength(1));
    expect(calls.single.$1, 'open');
    expect(
      calls.single.$2,
      const [
        'x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone',
      ],
    );
  });

  test('fails closed when macOS refuses to open settings', () async {
    final launcher = MacosAudioSettingsLauncher(
      runProcess: (_, __) async => 1,
    );

    await expectLater(
      launcher.openMicrophonePrivacy(),
      throwsStateError,
    );
  });
}
