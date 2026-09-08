/// Shared, provider-neutral models for non-real-time recording, lookup,
/// metadata, and session-history services.

enum ServiceOperationState { idle, running, retrying, succeeded, cancelled, failed }

enum ServiceFailureCode {
  invalidConfiguration,
  unavailable,
  permissionDenied,
  storageFull,
  writeFailed,
  queueOverflow,
  timeout,
  offline,
  rateLimited,
  unauthorized,
  malformedResponse,
  cancelled,
  unknown,
}

enum SampleFormat { pcm16, pcm24, float32 }

enum TrackProvenance { automatic, manual }

class ServiceStatus {
  const ServiceStatus._({
    required this.state,
    this.failureCode,
    this.message,
    this.attempt = 0,
    this.nextRetryAt,
  });

  const ServiceStatus.idle() : this._(state: ServiceOperationState.idle);
  const ServiceStatus.running({int attempt = 0})
      : this._(state: ServiceOperationState.running, attempt: attempt);
  const ServiceStatus.succeeded()
      : this._(state: ServiceOperationState.succeeded);
  const ServiceStatus.cancelled({String? message})
      : this._(
          state: ServiceOperationState.cancelled,
          failureCode: ServiceFailureCode.cancelled,
          message: message,
        );
  const ServiceStatus.retrying({
    required ServiceFailureCode failureCode,
    required int attempt,
    required DateTime nextRetryAt,
    String? message,
  }) : this._(
          state: ServiceOperationState.retrying,
          failureCode: failureCode,
          attempt: attempt,
          nextRetryAt: nextRetryAt,
          message: message,
        );
  const ServiceStatus.failed({
    required ServiceFailureCode failureCode,
    String? message,
    int attempt = 0,
  }) : this._(
          state: ServiceOperationState.failed,
          failureCode: failureCode,
          message: message,
          attempt: attempt,
        );

  final ServiceOperationState state;
  final ServiceFailureCode? failureCode;
  final String? message;
  final int attempt;
  final DateTime? nextRetryAt;

  bool get isTerminal =>
      state == ServiceOperationState.succeeded ||
      state == ServiceOperationState.cancelled ||
      state == ServiceOperationState.failed;
}

class RecordingConfig {
  const RecordingConfig({
    required this.destinationPath,
    required this.sampleRateHz,
    required this.channelCount,
    required this.sampleFormat,
    this.maxBytes,
  });

  final String destinationPath;
  final int sampleRateHz;
  final int channelCount;
  final SampleFormat sampleFormat;
  final int? maxBytes;

  int get bitsPerSample {
    switch (sampleFormat) {
      case SampleFormat.pcm16:
        return 16;
      case SampleFormat.pcm24:
        return 24;
      case SampleFormat.float32:
        return 32;
    }
  }

  ServiceFailureCode? get validationFailure {
    if (destinationPath.trim().isEmpty ||
        sampleRateHz <= 0 ||
        channelCount <= 0 ||
        (maxBytes != null && maxBytes! <= 0)) {
      return ServiceFailureCode.invalidConfiguration;
    }
    return null;
  }
}

class TracklistEntry {
  const TracklistEntry({
    required this.sessionId,
    required this.cueTime,
    required this.sourceId,
    required this.artist,
    required this.title,
    required this.confidence,
    required this.provenance,
    required this.createdAt,
    this.providerId,
    this.updatedAt,
  });

  final String sessionId;
  final Duration cueTime;
  final String sourceId;
  final String artist;
  final String title;
  final double confidence;
  final TrackProvenance provenance;
  final DateTime createdAt;
  final String? providerId;
  final DateTime? updatedAt;

  String get normalizedIdentity {
    final provider = providerId?.trim();
    if (provider != null && provider.isNotEmpty) return 'provider:$provider';
    String normalize(String value) =>
        value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return 'text:${normalize(artist)}|${normalize(title)}';
  }

  TracklistEntry applyManualCorrection({
    required String artist,
    required String title,
    required DateTime correctedAt,
  }) =>
      TracklistEntry(
        sessionId: sessionId,
        cueTime: cueTime,
        sourceId: sourceId,
        artist: artist,
        title: title,
        confidence: 1,
        provenance: TrackProvenance.manual,
        createdAt: createdAt,
        providerId: providerId,
        updatedAt: correctedAt,
      );
}

bool shouldSuppressAutomaticMatch({
  required TracklistEntry candidate,
  required Iterable<TracklistEntry> existing,
  required Duration debounceWindow,
}) {
  if (candidate.provenance != TrackProvenance.automatic) return false;
  return existing.any((entry) =>
      entry.provenance == TrackProvenance.automatic &&
      entry.normalizedIdentity == candidate.normalizedIdentity &&
      (entry.cueTime - candidate.cueTime).abs() <= debounceWindow);
}

String redactDiagnostic(String value) {
  final withoutBearerToken = value.replaceAll(
    RegExp(r'bearer\s+\S+', caseSensitive: false),
    'Bearer [REDACTED]',
  );
  return withoutBearerToken.replaceAll(
    RegExp(
      r'(authorization|token|password)\s*[:=]\s*[^\s&]+',
      caseSensitive: false,
    ),
    r'$1=[REDACTED]',
  );
}
