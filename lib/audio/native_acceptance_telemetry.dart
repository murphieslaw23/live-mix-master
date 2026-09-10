import 'native_audio_bindings.dart';
import 'native_audio_engine.dart';
import 'native_pcm_runtime_pump.dart';

class AcceptanceTelemetrySnapshot {
  const AcceptanceTelemetrySnapshot({
    required this.captureState,
    required this.sampleRate,
    required this.bufferFrames,
    required this.inputChannels,
    required this.formatFlags,
    required this.callbackCount,
    required this.xrunCount,
    required this.averageCallbackUs,
    required this.maxCallbackUs,
    required this.recorderQueueDepth,
    required this.fingerprintQueueDepth,
    required this.recorderRejectedBlocks,
    required this.fingerprintRejectedBlocks,
  });

  final NativeCaptureState? captureState;
  final double? sampleRate;
  final int? bufferFrames;
  final int? inputChannels;
  final int? formatFlags;
  final int callbackCount;
  final int xrunCount;
  final double averageCallbackUs;
  final double maxCallbackUs;
  final int recorderQueueDepth;
  final int fingerprintQueueDepth;
  final int recorderRejectedBlocks;
  final int fingerprintRejectedBlocks;

  bool get cleanHandoff =>
      recorderRejectedBlocks == 0 && fingerprintRejectedBlocks == 0;

  /// Deterministic, non-secret evidence suitable for pasting into the
  /// Issue #3 acceptance record.
  ///
  /// The snapshot type deliberately contains no endpoint UID, filesystem
  /// path, credential, account, or hardware serial fields, so this formatter
  /// cannot accidentally serialize them.
  String toEvidenceMarkdown() {
    final rate = sampleRate == null
        ? 'PENDING ACTIVE ROUTE'
        : '${sampleRate!.toStringAsFixed(0)} Hz';
    final frames = bufferFrames?.toString() ?? 'PENDING';
    final channels = inputChannels?.toString() ?? 'PENDING';
    final flags = formatFlags?.toString() ?? 'PENDING';
    final state = captureState?.name ?? 'unknown';
    final overflow = cleanHandoff ? 'CLEAN' : 'REJECTED BLOCKS';

    return <String>[
      '## Same-process E2E telemetry',
      '',
      '- capture state: $state',
      '- sample rate: $rate',
      '- buffer frames: $frames',
      '- input channels: $channels',
      '- format flags: $flags',
      '- callback count: $callbackCount',
      '- average callback duration (us): ${averageCallbackUs.toStringAsFixed(1)}',
      '- maximum callback duration (us): ${maxCallbackUs.toStringAsFixed(1)}',
      '- xrun count: $xrunCount',
      '- recorder queue depth observed: $recorderQueueDepth',
      '- fingerprint queue depth observed: $fingerprintQueueDepth',
      '- recorder rejected blocks: $recorderRejectedBlocks',
      '- fingerprint rejected blocks: $fingerprintRejectedBlocks',
      '- queue overflow result: $overflow',
    ].join('\n');
  }
}

abstract interface class AcceptanceTelemetrySource {
  AcceptanceTelemetrySnapshot get snapshot;
}

/// Read-only, non-real-time acceptance telemetry for the running Flutter host.
///
/// This object only samples state already published by the native control ABI
/// and the Dart host PCM pump. It is never called from the Core Audio callback
/// and intentionally carries no credentials, filesystem paths, serial numbers,
/// or unrelated endpoint identifiers.
class NativeRuntimeAcceptanceTelemetry implements AcceptanceTelemetrySource {
  const NativeRuntimeAcceptanceTelemetry({
    required this.audioEngine,
    required this.pcmRuntimePump,
  });

  final NativeAudioEngine audioEngine;
  final NativePcmRuntimePump pcmRuntimePump;

  @override
  AcceptanceTelemetrySnapshot get snapshot {
    final capture = audioEngine.captureStatus;
    final handoff = pcmRuntimePump.status;

    return AcceptanceTelemetrySnapshot(
      captureState: capture?.state,
      sampleRate: capture?.sampleRate,
      bufferFrames: capture?.bufferFrames,
      inputChannels: capture?.inputChannels,
      formatFlags: capture?.formatFlags,
      callbackCount: capture?.callbackCount ?? 0,
      xrunCount: capture?.xrunCount ?? 0,
      averageCallbackUs: capture?.averageCallbackUs ?? 0,
      maxCallbackUs: capture?.maxCallbackUs ?? 0,
      recorderQueueDepth: handoff.recorderQueueDepth,
      fingerprintQueueDepth: handoff.fingerprintQueueDepth,
      recorderRejectedBlocks: handoff.recorderRejectedBlocks,
      fingerprintRejectedBlocks: handoff.fingerprintRejectedBlocks,
    );
  }
}
