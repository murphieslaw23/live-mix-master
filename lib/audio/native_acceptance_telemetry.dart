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

  /// Deterministic, non-secret Markdown suitable for the Issue #3 evidence
  /// record. Endpoint identity, paths, credentials, account data and serial
  /// numbers are intentionally absent from this model.
  String toEvidenceMarkdown() {
    final rate = sampleRate == null
        ? 'PENDING ACTIVE ROUTE'
        : '${sampleRate!.toStringAsFixed(0)} Hz';
    final state = captureState?.name ?? 'unknown';
    final overflow = cleanHandoff ? 'CLEAN' : 'REJECTED BLOCKS';

    return <String>[
      '## Same-process E2E telemetry',
      '',
      '- capture state: $state',
      '- sample rate: $rate',
      '- buffer frames: ${bufferFrames?.toString() ?? 'PENDING'}',
      '- input channels: ${inputChannels?.toString() ?? 'PENDING'}',
      '- format flags: ${formatFlags?.toString() ?? 'PENDING'}',
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

/// Read-only, non-real-time acceptance telemetry for the current Flutter host.
/// It samples state already published by the native control ABI and PCM pump;
/// it is never called from the Core Audio IOProc.
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
