import 'package:flutter/material.dart';

import 'app/app_surface.dart';
import 'audio/audio_engine_factory.dart';
import 'audio/audio_engine_port.dart';
import 'design/live_mix_tokens.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final audioEngine = createAudioEnginePort();
  final audioEngineResult = audioEngine.initialize();
  runApp(
    LiveMixMasterApp(
      audioEngine: audioEngine,
      audioEngineResult: audioEngineResult,
    ),
  );
}

class LiveMixMasterApp extends StatelessWidget {
  const LiveMixMasterApp({
    super.key,
    this.audioEngine,
    this.audioEngineResult,
  });

  final AudioEnginePort? audioEngine;
  final AudioEngineBootstrapResult? audioEngineResult;

  @override
  Widget build(BuildContext context) {
    final result = audioEngineResult;
    return MaterialApp(
      title: 'LiveMixMaster',
      debugShowCheckedModeBanner: false,
      theme: LiveMixTheme.dark(),
      home: result == null || result.isAvailable
          ? buildPrimaryOperatorSurface(audioEngine)
          : _AudioEngineUnavailable(result: result),
    );
  }
}

class _AudioEngineUnavailable extends StatelessWidget {
  const _AudioEngineUnavailable({required this.result});

  final AudioEngineBootstrapResult result;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: LiveMixTokens.surfaceRack,
              border: Border.all(color: LiveMixTokens.meterClip),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AUDIO ENGINE UNAVAILABLE',
                  style: LiveMixTextStyles.sectionDisplay,
                ),
                const SizedBox(height: 16),
                Text(
                  result.message,
                  style: LiveMixTextStyles.body,
                ),
                if (result.diagnostics.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Diagnostics:\n${result.diagnostics.join('\n')}',
                    style: LiveMixTextStyles.numericTelemetry.copyWith(
                      fontSize: 12,
                      color: LiveMixTokens.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
