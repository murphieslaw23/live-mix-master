import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/material.dart';

import 'audio/audio_engine_bridge.dart';
import 'audio/native_audio_engine.dart';
import 'audio/native_audio_ffi_bindings.dart';
import 'audio/native_audio_permission_bindings.dart';
import 'audio/native_audio_runtime.dart';
import 'audio/native_library_loader.dart';
import 'audio/native_pcm_runtime_pump.dart';
import 'audio/native_recording_drain.dart';
import 'design/live_mix_tokens.dart';
import 'features/mixer/mixer_desk_view.dart';
import 'services/fingerprint_service.dart';
import 'services/lossless_recording_writer.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final nativeLibraryResult = NativeLibraryLoader.tryLoad();
  final library = nativeLibraryResult.library;
  final nativeRuntimeFuture =
      library == null ? null : _prepareNativeAppRuntime(library);

  runApp(
    LiveMixMasterApp(
      nativeLibraryResult: nativeLibraryResult,
      nativeRuntimeFuture: nativeRuntimeFuture,
    ),
  );
}

class NativeAppRuntime {
  NativeAppRuntime({
    required this.audioEngine,
    required this.recordingWriter,
    required this.fingerprintService,
    required this.pcmRuntimePump,
  });

  final AudioEngine audioEngine;
  final LosslessRecordingWriter recordingWriter;
  final FingerprintService fingerprintService;
  final NativePcmRuntimePump pcmRuntimePump;
}

Future<NativeAppRuntime> _prepareNativeAppRuntime(
  DynamicLibrary library,
) async {
  final bindings = FfiNativeAudioBindings(library);
  final runtime = NativeAudioRuntime(
    permissions: FfiAudioInputPermissionBindings(library),
    engineFactory: (permissionState) => NativeAudioEngine(
      bindings: bindings,
      permissionState: permissionState,
    ),
  );
  final engine = await runtime.prepare();

  final pcmSampleRate = _configuredPcmSampleRate();
  final recordingWriter = LosslessRecordingWriter(
    config: RecordingConfig(
      destinationDirectory: _recordingDirectory(),
      sampleRate: pcmSampleRate,
      channels: 2,
      bitDepth: PcmBitDepth.pcm32BitFloat,
    ),
  );
  final fingerprintService = FingerprintService(
    config: AudioFingerprintConfig(
      acoustIdApiKey: Platform.environment['ACOUSTID_API_KEY'] ?? '',
      sampleRate: pcmSampleRate,
      channels: 2,
    ),
  );
  await fingerprintService.start();

  final recordingDrain = NativeRecordingDrain(
    bindings: bindings,
    writer: recordingWriter,
  );
  final pcmRuntimePump = NativePcmRuntimePump(
    bindings: bindings,
    recordingDrain: recordingDrain,
    fingerprintSink: fingerprintService.pushPcmChunk,
  )..start();

  return NativeAppRuntime(
    audioEngine: engine,
    recordingWriter: recordingWriter,
    fingerprintService: fingerprintService,
    pcmRuntimePump: pcmRuntimePump,
  );
}

int _configuredPcmSampleRate() {
  final configured = int.tryParse(
    Platform.environment['LMM_RECORDING_SAMPLE_RATE'] ?? '',
  );
  if (configured != null && configured > 0) return configured;
  return 48000;
}

String _recordingDirectory() {
  final configured = Platform.environment['LMM_RECORDING_DIR']?.trim();
  if (configured != null && configured.isNotEmpty) return configured;
  return '${Directory.systemTemp.path}/LiveMixMaster';
}

class LiveMixMasterApp extends StatelessWidget {
  const LiveMixMasterApp({
    super.key,
    this.nativeLibraryResult,
    this.audioEngineFuture,
    this.nativeRuntimeFuture,
  });

  final NativeLibraryLoadResult? nativeLibraryResult;
  final Future<AudioEngine>? audioEngineFuture;
  final Future<NativeAppRuntime>? nativeRuntimeFuture;

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

    final runtimeFuture = nativeRuntimeFuture;
    if (runtimeFuture != null) {
      return FutureBuilder<NativeAppRuntime>(
        future: runtimeFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _NativeEnginePreparing();
          }
          if (snapshot.hasError) {
            return _NativeEngineStartupFailure(
              message: snapshot.error.toString(),
            );
          }
          final runtime = snapshot.data;
          if (runtime == null) {
            return const _NativeEngineStartupFailure(
              message: 'Native runtime completed without service wiring.',
            );
          }
          return _NativeMixerRuntimeHost(runtime: runtime);
        },
      );
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

class _NativeMixerRuntimeHost extends StatefulWidget {
  const _NativeMixerRuntimeHost({required this.runtime});

  final NativeAppRuntime runtime;

  @override
  State<_NativeMixerRuntimeHost> createState() => _NativeMixerRuntimeHostState();
}

class _NativeMixerRuntimeHostState extends State<_NativeMixerRuntimeHost> {
  @override
  void dispose() {
    widget.runtime.pcmRuntimePump.dispose();
    unawaited(widget.runtime.recordingWriter.dispose());
    unawaited(widget.runtime.fingerprintService.stop());
    unawaited(widget.runtime.audioEngine.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MixerDeskView(
      audioEngine: widget.runtime.audioEngine,
      recordingWriter: widget.runtime.recordingWriter,
      fingerprintService: widget.runtime.fingerprintService,
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
