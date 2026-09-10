import 'dart:async';
import 'dart:typed_data';

import 'native_pcm_handoff_bindings.dart';
import 'native_recording_drain.dart';

typedef FingerprintPcmSink = void Function(Float32List pcm);

class NativePcmDrainCycle {
  const NativePcmDrainCycle({
    required this.recordingBlocks,
    required this.fingerprintBlocks,
  });

  final int recordingBlocks;
  final int fingerprintBlocks;
}

/// Non-real-time host pump for the two native post-master SPSC queues.
///
/// The Core Audio callback only writes fixed native blocks. This class runs on
/// the Dart host event loop and drains those blocks into the recording writer
/// and fingerprint service without any callback into Dart from the audio thread.
class NativePcmRuntimePump {
  NativePcmRuntimePump({
    required this.bindings,
    required this.recordingDrain,
    this.fingerprintSink,
    this.interval = const Duration(milliseconds: 10),
    this.maxFingerprintBlocksPerDrain = 32,
  })  : assert(interval > Duration.zero),
        assert(maxFingerprintBlocksPerDrain > 0);

  final NativePcmHandoffBindings bindings;
  final NativeRecordingDrain recordingDrain;
  final FingerprintPcmSink? fingerprintSink;
  final Duration interval;
  final int maxFingerprintBlocksPerDrain;

  Timer? _timer;
  bool _draining = false;
  bool _disposed = false;

  int discardedFingerprintBlocks = 0;
  int? lastFingerprintSequence;

  bool get isRunning => _timer?.isActive ?? false;
  NativePcmHandoffStatus get status => bindings.status;

  void start() {
    if (_disposed) {
      throw StateError('NativePcmRuntimePump has already been disposed.');
    }
    if (_timer != null) return;

    drainNow();
    _timer = Timer.periodic(interval, (_) {
      if (!_disposed) drainNow();
    });
  }

  NativePcmDrainCycle drainNow() {
    if (_disposed || _draining) {
      return const NativePcmDrainCycle(
        recordingBlocks: 0,
        fingerprintBlocks: 0,
      );
    }

    _draining = true;
    try {
      final recordingBlocks = recordingDrain.drainNow();
      var fingerprintBlocks = 0;
      while (fingerprintBlocks < maxFingerprintBlocksPerDrain) {
        final block = bindings.popFingerprintBlock();
        if (block == null) break;

        fingerprintBlocks += 1;
        lastFingerprintSequence = block.sequence;
        final sink = fingerprintSink;
        if (sink == null) {
          discardedFingerprintBlocks += 1;
        } else {
          sink(block.interleavedStereo);
        }
      }

      return NativePcmDrainCycle(
        recordingBlocks: recordingBlocks,
        fingerprintBlocks: fingerprintBlocks,
      );
    } finally {
      _draining = false;
    }
  }

  void dispose() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = null;
    _disposed = true;
  }
}
