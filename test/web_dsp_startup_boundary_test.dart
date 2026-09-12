import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web DSP startup boundary is fixed, versioned, and fail-closed', () {
    final gateway = File(
      'lib/audio/web/browser_audio_worklet_gateway_web.dart',
    ).readAsStringSync();

    expect(
      gateway,
      contains("const String _dspAssetPath = 'audio/livemixmaster-dsp.wasm';"),
    );
    expect(gateway, contains('const int _dspAbiVersion = 1;'));
    expect(gateway, contains('final dspModule = await _compileDspModule();'));
    expect(gateway, contains("'type': 'dspInit'"));
    expect(gateway, contains("case 'dspReady':"));
    expect(gateway, contains('_dspHandshakeTimeout'));

    for (final message in const [
      'DSP MODULE UNAVAILABLE — AUDIO ENGINE NOT READY',
      'DSP MODULE VERSION MISMATCH — AUDIO ENGINE NOT READY',
      'DSP MODULE INITIALIZATION FAILED — AUDIO ENGINE NOT READY',
    ]) {
      expect(gateway, contains(message));
    }

    expect(
      gateway,
      isNot(contains("_dspAssetPath = '\${")),
      reason: 'canonical DSP asset path must not be derived from session/user data',
    );
  });
}
