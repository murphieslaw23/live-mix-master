enum AudioEngineKind {
  desktopNative,
  webBrowser,
  unsupported,
}

class AudioEngineBootstrapResult {
  const AudioEngineBootstrapResult._({
    required this.kind,
    required this.isAvailable,
    required this.message,
    required this.diagnostics,
  });

  const AudioEngineBootstrapResult.available({
    required AudioEngineKind kind,
    required String message,
    List<String> diagnostics = const [],
  }) : this._(
          kind: kind,
          isAvailable: true,
          message: message,
          diagnostics: diagnostics,
        );

  const AudioEngineBootstrapResult.unavailable({
    required AudioEngineKind kind,
    required String message,
    List<String> diagnostics = const [],
  }) : this._(
          kind: kind,
          isAvailable: false,
          message: message,
          diagnostics: diagnostics,
        );

  final AudioEngineKind kind;
  final bool isAvailable;
  final String message;
  final List<String> diagnostics;
}

abstract interface class AudioEnginePort {
  AudioEngineKind get kind;

  AudioEngineBootstrapResult initialize();
}
