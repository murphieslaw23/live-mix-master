import 'dart:typed_data';

import 'native_pcm_handoff_bindings.dart';

typedef NativeRecordingState = bool Function();
typedef NativeRecordingPcmSink = void Function(Float32List samples);

/// Bounded non-real-time drain from the native post-master queue into the
/// currently negotiated recording consumer.
///
/// Blocks produced before RECORD is armed are discarded deliberately so a new
/// recording cannot begin with stale pre-roll audio.
class NativeRecordingDrain {
  NativeRecordingDrain({
    required this.bindings,
    required this.isRecording,
    required this.recordingSink,
    this.maxBlocksPerDrain = 32,
  }) : assert(maxBlocksPerDrain > 0);

  final NativePcmHandoffBindings bindings;
  final NativeRecordingState isRecording;
  final NativeRecordingPcmSink recordingSink;
  final int maxBlocksPerDrain;

  int discardedBlocks = 0;
  int? lastSequence;

  NativePcmHandoffStatus get status => bindings.status;

  int drainNow() {
    var drained = 0;
    while (drained < maxBlocksPerDrain) {
      final block = bindings.popRecordingBlock();
      if (block == null) break;
      drained += 1;
      lastSequence = block.sequence;

      if (!isRecording()) {
        discardedBlocks += 1;
        continue;
      }

      recordingSink(block.interleavedStereo);
    }
    return drained;
  }
}
