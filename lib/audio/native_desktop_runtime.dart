import 'dart:ffi';
import 'dart:io';

import 'audio_engine_bridge.dart';
import 'native_audio_engine.dart';
import 'native_audio_ffi_bindings.dart';
import 'native_audio_permission_bindings.dart';
import 'native_audio_runtime.dart';
import 'native_pcm_runtime_pump.dart';
import 'native_pcm_service_coordinator.dart';
import 'native_recording_drain.dart';

/// Application-scoped owner for the desktop native audio runtime.
///
/// Native callbacks stay entirely in C/C++. Recorder/fingerprint consumers are
/// activated only after capture publishes its negotiated running format; only
/// then is the non-real-time PCM pump started.
class NativeDesktopRuntime {
  NativeDesktopRuntime._({
    required this.library,
    required this.audioEngine,
    this.services,
    this.pcmRuntimePump,
  });

  final DynamicLibrary library;
  final AudioEngine audioEngine;
  final NativePcmServiceCoordinator? services;
  final NativePcmRuntimePump? pcmRuntimePump;

  static Future<NativeDesktopRuntime> create(DynamicLibrary library) async {
    final permissions = FfiAudioInputPermissionBindings(library);
    final bindings = FfiNativeAudioBindings(library);
    final services = NativePcmServiceCoordinator(
      destinationDirectory: _recordingDirectory(),
      acoustIdApiKey: Platform.environment['ACOUSTID_API_KEY'] ?? '',
    );
    final recordingDrain = NativeRecordingDrain(
      bindings: bindings,
      isRecording: () => services.isRecording,
      recordingSink: services.pushRecordingPcm,
    );
    final pump = NativePcmRuntimePump(
      bindings: bindings,
      recordingDrain: recordingDrain,
      fingerprintSink: services.pushFingerprintPcm,
    );

    final runtime = NativeAudioRuntime(
      permissions: permissions,
      engineFactory: (permissionState) => NativeAudioEngine(
        bindings: bindings,
        permissionState: permissionState,
        permissionStateProvider: permissions.readStatus,
        requestPermission: permissions.request,
        onCaptureStarted: (status) async {
          await services.activateForCapture(status);
          pump.start();
        },
        onCaptureStopped: () {
          pump.stop();
        },
      ),
    );

    try {
      final engine = await runtime.prepare();
      return NativeDesktopRuntime._(
        library: library,
        audioEngine: engine,
        services: services,
        pcmRuntimePump: pump,
      );
    } catch (_) {
      pump.dispose();
      await services.dispose();
      rethrow;
    }
  }

  factory NativeDesktopRuntime.testing({
    required AudioEngine audioEngine,
    NativePcmServiceCoordinator? services,
    NativePcmRuntimePump? pcmRuntimePump,
  }) {
    return NativeDesktopRuntime._(
      library: DynamicLibrary.process(),
      audioEngine: audioEngine,
      services: services,
      pcmRuntimePump: pcmRuntimePump,
    );
  }

  Future<void> dispose() async {
    await audioEngine.dispose();
    pcmRuntimePump?.dispose();
    await services?.dispose();
  }

  static String _recordingDirectory() {
    final configured = Platform.environment['LMM_RECORDING_DIR']?.trim();
    if (configured != null && configured.isNotEmpty) return configured;
    return '${Directory.systemTemp.path}/LiveMixMaster';
  }
}
