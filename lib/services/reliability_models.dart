/// Shared, provider-neutral models for non-real-time recording, lookup,
/// metadata, and session-history services.

enum ServiceOperationState { idle, running, retrying, succeeded, cancelled, failed }

enum ServiceFailureCode {
  invalidConfiguration, unavailable, permissionDenied, storageFull, writeFailed,
  queueOverflow, timeout, offline, rateLimited, unauthorized, malformedResponse,
  cancelled, unknown,
}

enum SampleFormat { pcm16, pcm24, float32 }
enum TrackProvenance { automatic, manual }

class ServiceStatus {
  const ServiceStatus._({required this.state, this.failureCode, this.message, this.attempt = 0, this.nextRetryAt});
  const ServiceStatus.idle() : this._(state: ServiceOperationState.idle);
  const ServiceStatus.running({int attempt = 0}) : this._(state: ServiceOperationState.running, attempt: attempt);
  const ServiceStatus.succeeded() : this._(state: ServiceOperationState.succeeded);
  const ServiceStatus.cancelled({String? message}) : this._(state: ServiceOperationState.cancelled, failureCode: ServiceFailureCode.cancelled, message: message);
  const ServiceStatus.retrying({required ServiceFailureCode failureCode, required int attempt, required DateTime nextRetryAt, String? message}) : this._(state: ServiceOperationState.retrying, failureCode: failureCode, attempt: attempt, nextRetryAt: nextRetryAt, message: message);
  const ServiceStatus.failed({required ServiceFailureCode failureCode, String? message, int attempt = 0}) : this._(state: ServiceOperationState.failed, failureCode: failureCode, message: message, attempt: attempt);
  final ServiceOperationState state;
  final ServiceFailureCode? failureCode;
  final String? message;
  final int attempt;
  final DateTime? nextRetryAt;
  bool get isTerminal => state == ServiceOperationState.succeeded || state == ServiceOperationState.cancelled || state == ServiceOperationState.failed;
}

class RecordingConfig {
  const RecordingConfig({required this.destinationPath, required this.sampleRateHz, required this.channelCount, required this.sampleFormat, this.maxBytes});
  final String destinationPath;
  final int sampleRateHz;
  final int channelCount;
  final SampleFormat sampleFormat;
  final int? maxBytes;
  int get bitsPerSample => sampleFormat == SampleFormat.pcm16 ? 16 : sampleFormat == SampleFormat.pcm24 ? 24 : 32;
  ServiceFailureCode? get validationFailure => destinationPath.trim().isEmpty || sampleRateHz <= 0 || channelCount <= 0 || (maxBytes != null && maxBytes! <= 0) ? ServiceFailureCode.invalidConfiguration : null;
}

class TracklistEntry {
  const TracklistEntry({required this.sessionId, required this.cueTime, required this.sourceId, required this.artist, required this.title, required this.confidence, required this.provenance, required this.createdAt, this.providerId, this.updatedAt});
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
    String normalize(String value) => value.trim().split(' ').where((part) => part.isNotEmpty).join(' ').toLowerCase();
    return 'text:${normalize(artist)}|${normalize(title)}';
  }
  TracklistEntry applyManualCorrection({required String artist, required String title, required DateTime correctedAt}) => TracklistEntry(sessionId: sessionId, cueTime: cueTime, sourceId: sourceId, artist: artist, title: title, confidence: 1, provenance: TrackProvenance.manual, createdAt: createdAt, providerId: providerId, updatedAt: correctedAt);
}

bool shouldSuppressAutomaticMatch({required TracklistEntry candidate, required Iterable<TracklistEntry> existing, required Duration debounceWindow}) {
  if (candidate.provenance != TrackProvenance.automatic) return false;
  return existing.any((entry) => entry.provenance == TrackProvenance.automatic && entry.normalizedIdentity == candidate.normalizedIdentity && (entry.cueTime - candidate.cueTime).abs() <= debounceWindow);
}

/// Defense in depth for legacy text. Prefer allowlisted messages, not raw errors.
String redactDiagnostic(String value) {
  if (value.length > 2048) return '[REDACTED: diagnostic too long]';
  var safe = value.replaceAll(
    RegExp(r'''\b[a-z][a-z0-9+.-]*://[^\s"'<>]+''', caseSensitive: false),
    '[REDACTED_URL]',
  );
  safe = safe.replaceAll(
    RegExp(r'\b(?:proxy-)?authorization\s*[:=]\s*[^\r\n]*', caseSensitive: false),
    'Authorization=[REDACTED]',
  );
  safe = safe.replaceAll(RegExp(r'\bBasic\s+[A-Za-z0-9+/=]+', caseSensitive: false), 'Basic [REDACTED]');
  safe = safe.replaceAll(RegExp(r'\bBearer\s+\S+', caseSensitive: false), 'Bearer [REDACTED]');
  safe = safe.replaceAllMapped(
    RegExp(r'''\b(password|pass|token|access_token|refresh_token|api_key|apikey|secret)\s*[:=]\s*(?:"[^"]*"|'[^']*'|[^\s&;,]+)''', caseSensitive: false),
    (match) => '${match.group(1)}=[REDACTED]',
  );
  return safe.replaceAll(RegExp(r'[\x00-\x1f\x7f\u2028\u2029]'), ' ');
}
