import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web DSP startup boundary is fixed, versioned, and fail-closed', () {
    final gateway = File(
      'lib/audio/web/browser_audio_worklet_gateway_web.dart',
    ).readAsStringSync();
    final worklet = File(
      'web/audio/livemixmaster-worklet.js',
    ).readAsStringSync();

    expect(
      gateway,
      contains("const String _dspAssetPath = 'audio/livemixmaster-dsp.wasm';"),
    );
    expect(gateway, contains('const int _dspAbiVersion = 1;'));
    expect(gateway, contains('final dspModule = await _compileDspModule();'));
    expect(gateway, contains("initMessage['type'] = 'dspInit'.toJS;"));
    expect(gateway, contains("case 'dspReady':"));
    expect(gateway, contains('_dspHandshakeTimeout'));
    expect(gateway, contains('BrowserAudioProcessingLifecycleGateway'));
    expect(gateway, contains('_dspRuntimeReady = false;'));
    expect(gateway, contains('_handleRuntimeDspFailure('));

    for (final message in const [
      'DSP MODULE UNAVAILABLE — AUDIO ENGINE NOT READY',
      'DSP MODULE VERSION MISMATCH — AUDIO ENGINE NOT READY',
      'DSP MODULE INITIALIZATION FAILED — AUDIO ENGINE NOT READY',
      'DSP RENDER QUANTUM EXCEEDED — AUDIO ENGINE NOT READY',
      'DSP MEMORY CHANGED — AUDIO ENGINE NOT READY',
      'DSP PROCESS FAILED — AUDIO ENGINE NOT READY',
      'DSP CHANNEL LIMIT EXCEEDED — AUDIO ENGINE NOT READY',
    ]) {
      expect(gateway, contains(message));
    }

    expect(
      gateway,
      contains('if (workletNode == null || !_dspRuntimeReady)'),
      reason: 'mixer configuration must fail closed after a runtime DSP failure',
    );
    expect(
      gateway,
      contains("'RECORDING UNAVAILABLE — AUDIO ENGINE NOT READY'"),
      reason: 'recording must not start when canonical DSP readiness is lost',
    );
    expect(
      gateway,
      isNot(contains("_dspAssetPath = '\${")),
      reason: 'canonical DSP asset path must not be derived from session/user data',
    );
    expect(
      worklet,
      isNot(contains('processWithJavaScriptDsp')),
      reason: 'release worklet must not retain a migration JavaScript DSP fallback',
    );
  });
}
