import '../services/lossless_recording_writer.dart';
import 'native_pcm_handoff_bindings.dart';

/// Bounded non-real-time drain from the native post-master queue into the WAV
/// writer. Blocks produced before RECORD is armed are discarded deliberately so
/// a new recording cannot begin with stale pre-roll audio.
class NativeRecordingDrain {
  NativeRecordingDrain({
    required this.bindings,
    required this.writer,
    this.maxBlocksPerDrain = 32,
  }) : assert(maxBlocksPerDrain > 0);

  final NativePcmHandoffBindings bindings;
  final LosslessRecordingWriter writer;
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

      if (!writer.isRecording) {
        discardedBlocks += 1;
        continue;
      }

      writer.writeStereoSamples(block.interleavedStereo);
    }
    return drained;
  }
}
