import 'browser_fingerprint_preparation_gateway.dart';

BrowserFingerprintPreparationGateway createBrowserFingerprintPreparationGateway() {
  return _UnsupportedBrowserFingerprintPreparationGateway();
}

class _UnsupportedBrowserFingerprintPreparationGateway
    implements BrowserFingerprintPreparationGateway {
  @override
  Future<PreparedBrowserFingerprint> prepare({
    required List<double> interleavedSamples,
    required int sampleRate,
    int channels = 2,
  }) async {
    throw const BrowserFingerprintPreparationException(
      BrowserFingerprintPreparationFailure.unsupported,
      'FINGERPRINT PREPARATION UNSUPPORTED ON THIS PLATFORM',
    );
  }

  @override
  Future<void> dispose() async {}
}
