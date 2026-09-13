import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const scriptPath = 'tool/macos_device_acceptance.sh';

  test('macOS device acceptance helper exposes a local-only fail-closed contract', () async {
    final help = await Process.run('bash', [scriptPath, '--help']);

    expect(help.exitCode, 0);
    final helpText = '${help.stdout}${help.stderr}';
    expect(helpText, contains('--preflight'));
    expect(helpText, contains('--launch'));
    expect(helpText, contains('real macOS'));

    final blocked = await Process.run(
      'bash',
      [scriptPath, '--preflight'],
      environment: <String, String>{...Platform.environment, 'CI': 'true'},
    );

    expect(blocked.exitCode, 64);
    expect(
      '${blocked.stdout}${blocked.stderr}',
      contains('interactive local macOS host'),
    );
  });

  test('acceptance helper preserves the real-device gate', () {
    final source = File(scriptPath).readAsStringSync();

    expect(source, contains('git rev-parse HEAD'));
    expect(source, contains('uname -s'));
    expect(source, contains('ctest --test-dir build/native --output-on-failure'));
    expect(source, contains('build/native/macos_device_probe --list'));
    expect(source, contains('flutter run -d macos'));
    expect(source, contains('docs/audio/issue3-device-acceptance-record.md'));
    expect(source, isNot(contains('Final result: PASS')));
    expect(source, isNot(contains('PENDING REAL DEVICE RUN" "PASS')));
  });
}
