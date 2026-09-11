import 'audio_engine_port.dart';

class UnsupportedAudioEngine implements AudioEnginePort {
  const UnsupportedAudioEngine();

  @override
  AudioEngineKind get kind => AudioEngineKind.unsupported;

  @override
  AudioEngineBootstrapResult initialize() {
    return const AudioEngineBootstrapResult.unavailable(
      kind: AudioEngineKind.unsupported,
      message: 'No supported LiveMixMaster audio backend is available on this platform.',
    );
  }
}

AudioEnginePort createAudioEnginePort() => const UnsupportedAudioEngine();
