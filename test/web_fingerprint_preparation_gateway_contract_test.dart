import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/services/web/browser_fingerprint_preparation_gateway.dart';
import 'package:live_mix_master/services/web/browser_fingerprint_preparation_runtime.dart';

void main() {
  test('VM runtime fails explicitly instead of fabricating a fingerprint', () async {
    final gateway = createBrowserFingerprintPreparationGateway();

    await expectLater(
      gateway.prepare(
        interleavedSamples: List<double>.filled(960000, 0),
        sampleRate: 48000,
        channels: 2,
      ),
      throwsA(
        isA<BrowserFingerprintPreparationException>()
            .having(
              (failure) => failure.failure,
              'failure',
              BrowserFingerprintPreparationFailure.unsupported,
            )
            .having(
              (failure) => failure.message,
              'message',
              'FINGERPRINT PREPARATION UNSUPPORTED ON THIS PLATFORM',
            ),
      ),
    );
  });

  test('runtime selects the Worker implementation only for browser builds', () async {
    final runtimeSource = await File(
      'lib/services/web/browser_fingerprint_preparation_runtime.dart',
    ).readAsString();
    final webSource = await File(
      'lib/services/web/browser_fingerprint_preparation_gateway_web.dart',
    ).readAsString();
    final controllerSource = await File(
      'lib/services/web/browser_fingerprint_preparation_controller.dart',
    ).readAsString();

    expect(runtimeSource, contains("if (dart.library.js_interop)"));
    expect(runtimeSource, contains('browser_fingerprint_preparation_gateway_web.dart'));
    expect(webSource, contains("fingerprint/livemixmaster-fingerprint-worker.js"));
    expect(webSource, contains("fingerprint/vendor/livemixmaster-chromaprint.mjs"));
    expect(webSource, contains("fingerprint/vendor/livemixmaster-chromaprint-core.wasm"));
    expect(webSource, isNot(contains('FingerprintProxyClient')));
    expect(webSource, isNot(contains('ACOUSTID')));
    expect(controllerSource, isNot(contains('FingerprintProxyClient')));
    expect(controllerSource, isNot(contains('ACOUSTID')));
    expect(controllerSource, isNot(contains('/api/fingerprint-lookup')));
  });
}
