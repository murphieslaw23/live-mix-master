import 'package:flutter/material.dart';

import '../audio/audio_engine_factory_desktop.dart';
import '../audio/audio_engine_port.dart';
import '../audio/native_desktop_runtime.dart';
import '../design/live_mix_tokens.dart';
import '../features/mixer/mixer_desk_view.dart';

Widget buildPrimaryOperatorSurface(AudioEnginePort? audioEngine) {
  if (audioEngine is! DesktopNativeAudioEngine) {
    return const MixerDeskView();
  }
  return _NativeDesktopOperatorSurface(audioEngine: audioEngine);
}

class _NativeDesktopOperatorSurface extends StatelessWidget {
  const _NativeDesktopOperatorSurface({required this.audioEngine});

  final DesktopNativeAudioEngine audioEngine;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<NativeDesktopRuntime>(
      future: audioEngine.prepareRuntime(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: LiveMixTokens.surfaceBase,
            body: Center(
              child: Text(
                'PREPARING AUDIO ENGINE',
                style: LiveMixTextStyles.sectionDisplay,
              ),
            ),
          );
        }
        if (snapshot.hasError || snapshot.data == null) {
          return Scaffold(
            backgroundColor: LiveMixTokens.surfaceBase,
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Text(
                  'AUDIO ENGINE STARTUP FAILED\n${snapshot.error ?? 'Native runtime returned no engine.'}',
                  style: LiveMixTextStyles.body,
                ),
              ),
            ),
          );
        }
        return MixerDeskView(audioEngine: snapshot.data!.audioEngine);
      },
    );
  }
}
