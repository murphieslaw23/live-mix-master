import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/native_pcm_handoff_bindings.dart';
import 'package:live_mix_master/audio/native_recording_drain.dart';

void main() {
  group('NativeRecordingDrain', () {
    test('discards pre-record PCM and forwards only armed blocks', () {
      final bindings = _FakePcmHandoffBindings();
      var recording = false;
      final received = <Float32List>[];
      final drain = NativeRecordingDrain(
        bindings: bindings,
        isRecording: () => recording,
        recordingSink: received.add,
      );

      bindings.recordingBlocks.add(_block(sequence: 1, value: .1));
      expect(drain.drainNow(), 1);
      expect(drain.discardedBlocks, 1);
      expect(received, isEmpty);

      recording = true;
      bindings.recordingBlocks
        ..add(_block(sequence: 2, value: .25))
        ..add(_block(sequence: 3, value: -.5));

      expect(drain.drainNow(), 2);
      expect(received, hasLength(2));
      expect(received.first.first, closeTo(.25, .00001));
      expect(received.last.first, closeTo(-.5, .00001));
      expect(drain.lastSequence, 3);
    });

    test('drain is bounded and exposes native queue rejection counters', () {
      final bindings = _FakePcmHandoffBindings(
        status: const NativePcmHandoffStatus(
          recorderQueueDepth: 9,
          fingerprintQueueDepth: 2,
          recorderRejectedBlocks: 4,
          fingerprintRejectedBlocks: 1,
        ),
      );
      final drain = NativeRecordingDrain(
        bindings: bindings,
        isRecording: () => false,
        recordingSink: (_) {},
        maxBlocksPerDrain: 2,
      );
      bindings.recordingBlocks.addAll([
        _block(sequence: 1, value: .1),
        _block(sequence: 2, value: .2),
        _block(sequence: 3, value: .3),
      ]);

      expect(drain.drainNow(), 2);
      expect(bindings.recordingBlocks, hasLength(1));
      expect(drain.status.recorderRejectedBlocks, 4);
      expect(drain.status.fingerprintRejectedBlocks, 1);
    });
  });
}

NativePcmBlock _block({required int sequence, required double value}) {
  return NativePcmBlock(
    frames: 4,
    sequence: sequence,
    interleavedStereo: Float32List.fromList(List<double>.filled(8, value)),
  );
}

class _FakePcmHandoffBindings implements NativePcmHandoffBindings {
  _FakePcmHandoffBindings({
    this.status = const NativePcmHandoffStatus(
      recorderQueueDepth: 0,
      fingerprintQueueDepth: 0,
      recorderRejectedBlocks: 0,
      fingerprintRejectedBlocks: 0,
    ),
  });

  final List<NativePcmBlock> recordingBlocks = <NativePcmBlock>[];
  final List<NativePcmBlock> fingerprintBlocks = <NativePcmBlock>[];

  @override
  final NativePcmHandoffStatus status;

  @override
  NativePcmBlock? popRecordingBlock() =>
      recordingBlocks.isEmpty ? null : recordingBlocks.removeAt(0);

  @override
  NativePcmBlock? popFingerprintBlock() =>
      fingerprintBlocks.isEmpty ? null : fingerprintBlocks.removeAt(0);
}
