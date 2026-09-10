import 'dart:ffi';

import 'package:flutter/material.dart';

import 'audio/audio_engine_bridge.dart';
import 'audio/native_audio_engine.dart';
import 'audio/native_audio_ffi_bindings.dart';
import 'audio/native_audio_permission_bindings.dart';
import 'audio/native_audio_runtime.dart';
import 'audio/native_library_loader.dart';
import 'design/live_mix_tokens.dart';
import 'features/mixer/mixer_desk_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final nativeLibraryResult = NativeLibraryLoader.tryLoad();
  final library = nativeLibraryResult.library;
  final audioEngineFuture = library == null
      ? null
      : _prepareNativeAudioEngine(library);

  runApp(
    LiveMixMasterApp(
      nativeLibraryResult: nativeLibraryResult,
      audioEngineFuture: audioEngineFuture,
    ),
  );
}

Future<AudioEngine> _prepareNativeAudioEngine(DynamicLibrary library) async {
  final runtime = NativeAudioRuntime(
    permissions: FfiAudioInputPermissionBindings(library),
    engineFactory: (permissionState) => NativeAudioEngine(
      bindings: FfiNativeAudioBindings(library),
      permissionState: permissionState,
    ),
  );
  return runtime.prepare();
}

class LiveMixMasterApp extends StatelessWidget {
  const LiveMixMasterApp({
    Key? key,
    this.nativeLibraryResult,
    this.audioEngineFuture,
  }) : super(key: key);

  final NativeLibraryLoadResult? nativeLibraryResult;
  final Future<AudioEngine>? audioEngineFuture;

  @override
  Widget build(BuildContext context) {
    final result = nativeLibraryResult;
    return MaterialApp(
      title: 'LiveMixMaster',
      debugShowCheckedModeBanner: false,
      theme: LiveMixTheme.dark(),
      home: _buildHome(result),
    );
  }

  Widget _buildHome(NativeLibraryLoadResult? result) {
    if (result == null) {
      return const MixerDeskView();
    }
    if (!result.isLoaded) {
      return _NativeEngineUnavailable(result: result);
    }

    final future = audioEngineFuture;
    if (future == null) {
      return const _NativeEngineStartupFailure(
        message: 'Loaded native engine has no configured host runtime.',
      );
    }

    return FutureBuilder<AudioEngine>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _NativeEnginePreparing();
        }
        if (snapshot.hasError) {
          return _NativeEngineStartupFailure(
            message: snapshot.error.toString(),
          );
        }
        final engine = snapshot.data;
        if (engine == null) {
          return const _NativeEngineStartupFailure(
            message: 'Native audio runtime completed without an engine.',
          );
        }
        return MixerDeskView(audioEngine: engine);
      },
    );
  }
}

class _NativeEnginePreparing extends StatelessWidget {
  const _NativeEnginePreparing();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'PREPARING AUDIO ENGINE',
          style: LiveMixTextStyles.sectionDisplay,
        ),
      ),
    );
  }
}

class _NativeEngineStartupFailure extends StatelessWidget {
  const _NativeEngineStartupFailure({required this.message});

  final String message;

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
                  'AUDIO ENGINE STARTUP FAILED',
                  style: LiveMixTextStyles.sectionDisplay,
                ),
                const SizedBox(height: 16),
                Text(message, style: LiveMixTextStyles.body),
              ],
            ),
          ),
        ),
      ),
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
