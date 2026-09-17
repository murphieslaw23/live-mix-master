import 'package:flutter/material.dart';

import '../audio/audio_engine_port.dart';
import '../design/live_mix_tokens.dart';

Widget buildPrimaryOperatorSurface(AudioEnginePort? _) {
  return const Scaffold(
    backgroundColor: LiveMixTokens.surfaceBase,
    body: Center(
      child: Text(
        'UNSUPPORTED PLATFORM',
        style: LiveMixTextStyles.sectionDisplay,
      ),
    ),
  );
}
