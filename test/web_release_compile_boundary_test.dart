import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/audio_engine_factory.dart';
import 'package:live_mix_master/audio/audio_engine_port.dart';

void main() {
  test('VM bootstrap selects the desktop native backend', () {
    final port = createAudioEnginePort();

    expect(port.kind, AudioEngineKind.desktopNative);
  });

  test('bootstrap result is platform-neutral', () {
    const result = AudioEngineBootstrapResult.available(
      kind: AudioEngineKind.webBrowser,
      message: 'Browser audio backend ready',
    );

    expect(result.isAvailable, isTrue);
    expect(result.kind, AudioEngineKind.webBrowser);
    expect(result.message, 'Browser audio backend ready');
    expect(result.diagnostics, isEmpty);
  });
}
