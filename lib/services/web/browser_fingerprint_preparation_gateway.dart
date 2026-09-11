enum BrowserFingerprintPreparationFailure {
  unsupported,
  invalidAudio,
  tooShort,
  busy,
  timeout,
  unavailable,
  disposed,
}

class PreparedBrowserFingerprint {
  final String fingerprint;
  final int durationSeconds;

  const PreparedBrowserFingerprint({
    required this.fingerprint,
    required this.durationSeconds,
  });
}

class BrowserFingerprintPreparationException implements Exception {
  final BrowserFingerprintPreparationFailure failure;
  final String message;

  const BrowserFingerprintPreparationException(this.failure, this.message);

  @override
  String toString() => 'BrowserFingerprintPreparationException($failure)';
}

abstract interface class BrowserFingerprintPreparationGateway {
  Future<PreparedBrowserFingerprint> prepare({
    required List<double> interleavedSamples,
    required int sampleRate,
    int channels = 2,
  });

  Future<void> dispose();
}
