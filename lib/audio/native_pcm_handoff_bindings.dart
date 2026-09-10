import 'dart:typed_data';

class NativePcmBlock {
  const NativePcmBlock({
    required this.frames,
    required this.sequence,
    required this.interleavedStereo,
  });

  final int frames;
  final int sequence;
  final Float32List interleavedStereo;
}

class NativePcmHandoffStatus {
  const NativePcmHandoffStatus({
    required this.recorderQueueDepth,
    required this.fingerprintQueueDepth,
    required this.recorderRejectedBlocks,
    required this.fingerprintRejectedBlocks,
  });

  final int recorderQueueDepth;
  final int fingerprintQueueDepth;
  final int recorderRejectedBlocks;
  final int fingerprintRejectedBlocks;
}

/// Non-real-time consumer seam for post-master PCM copied by the native engine.
///
/// The real-time callback only pushes bounded native blocks. Dart may pop those
/// blocks later on the host event loop and must never be invoked by the callback.
abstract interface class NativePcmHandoffBindings {
  NativePcmBlock? popRecordingBlock();
  NativePcmHandoffStatus get status;
}
