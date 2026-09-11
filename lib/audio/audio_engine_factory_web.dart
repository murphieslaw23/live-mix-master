import 'audio_engine_port.dart';

class WebAudioEngine implements AudioEnginePort {
  const WebAudioEngine();

  @override
  AudioEngineKind get kind => AudioEngineKind.webBrowser;

  @override
  AudioEngineBootstrapResult initialize() {
    return const AudioEngineBootstrapResult.available(
      kind: AudioEngineKind.webBrowser,
      message: 'Browser audio backend ready; source permission is required before capture.',
    );
  }
}

AudioEnginePort createAudioEnginePort() => const WebAudioEngine();
