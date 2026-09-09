import 'package:flutter/material.dart';

import 'audio/native_library_loader.dart';
import 'design/live_mix_tokens.dart';
import 'features/mixer/mixer_desk_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final nativeLibraryResult = NativeLibraryLoader.tryLoad();
  runApp(LiveMixMasterApp(nativeLibraryResult: nativeLibraryResult));
}

class LiveMixMasterApp extends StatelessWidget {
  const LiveMixMasterApp({
    Key? key,
    this.nativeLibraryResult,
  }) : super(key: key);

  final NativeLibraryLoadResult? nativeLibraryResult;

  @override
  Widget build(BuildContext context) {
    final result = nativeLibraryResult;
    return MaterialApp(
      title: 'LiveMixMaster',
      debugShowCheckedModeBanner: false,
      theme: LiveMixTheme.dark(),
      home: result == null || result.isLoaded
          ? const MixerDeskView()
          : _NativeEngineUnavailable(result: result),
    );
  }
}

class _NativeEngineUnavailable extends StatelessWidget {
  const _NativeEngineUnavailable({required this.result});

  final NativeLibraryLoadResult result;

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
                  'NATIVE ENGINE UNAVAILABLE',
                  style: LiveMixTextStyles.sectionDisplay,
                ),
                const SizedBox(height: 16),
                Text(
                  result.message,
                  style: LiveMixTextStyles.body,
                ),
                const SizedBox(height: 16),
                Text(
                  'Searched paths:\n${result.searchedPaths.join('\n')}',
                  style: LiveMixTextStyles.numericTelemetry.copyWith(
                    fontSize: 12,
                    color: LiveMixTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
