import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../lib/services/lossless_recording_writer.dart';
import '../lib/services/reliability_models.dart' as reliability;

class WavHeader {
  WavHeader(Uint8List bytes)
      : dataLength = ByteData.sublistView(bytes).getUint32(40, Endian.little),
        riffSize = ByteData.sublistView(bytes).getUint32(4, Endian.little),
        format = ByteData.sublistView(bytes).getUint16(20, Endian.little),
        channels = ByteData.sublistView(bytes).getUint16(22, Endian.little),
        sampleRate = ByteData.sublistView(bytes).getUint32(24, Endian.little),
        byteRate = ByteData.sublistView(bytes).getUint32(28, Endian.little),
        blockAlign = ByteData.sublistView(bytes).getUint16(32, Endian.little),
        bitDepth = ByteData.sublistView(bytes).getUint16(34, Endian.little) {
    expect(bytes.sublist(0, 4), [82, 73, 70, 70]);
    expect(bytes.sublist(8, 12), [87, 65, 86, 69]);
    expect(bytes.sublist(12, 16), [102, 109, 116, 32]);
    expect(bytes.sublist(36, 40), [100, 97, 116, 97]);
  }
  final int riffSize, dataLength, format, channels, sampleRate, byteRate, blockAlign, bitDepth;
}

void main() {
  group('LosslessRecordingWriter WAV contract', () {
    late Directory directory;

    setUp(() async => directory = await Directory.systemTemp.createTemp('lmm_wav_test_'));
    tearDown(() async => directory.delete(recursive: true));

    for (final value in <({PcmBitDepth depth, int bits, int format})>[
      (depth: PcmBitDepth.pcm16Bit, bits: 16, format: 1),
      (depth: PcmBitDepth.pcm24Bit, bits: 24, format: 1),
      (depth: PcmBitDepth.pcm32BitFloat, bits: 32, format: 3),
    ]) {
      test('${value.bits}-bit WAV has a valid independent RIFF header', () async {
        final writer = LosslessRecordingWriter(config: RecordingConfig(destinationDirectory: directory.path, bitDepth: value.depth));
        final path = await writer.startRecording();
        writer.writeStereoSamples(Float32List.fromList([-1, -0.5, 0, 0.5, 1, 0.25]));
        final stats = await writer.stopRecording();
        final bytes = await File(path).readAsBytes();
        final wav = WavHeader(bytes);
        expect(wav.format, value.format);
        expect(wav.bitDepth, value.bits);
        expect(wav.channels, 2);
        expect(wav.sampleRate, 48000);
        expect(wav.blockAlign, value.bits ~/ 4);
        expect(wav.byteRate, 48000 * wav.blockAlign);
        expect(wav.dataLength, 3 * wav.blockAlign);
        expect(wav.riffSize, bytes.length - 8);
        expect(stats.totalBytesWritten, bytes.length);
        await writer.dispose();
      });
    }

    test('invalid configuration emits typed failure before creating a file', () async {
      final writer = LosslessRecordingWriter(config: const RecordingConfig(destinationDirectory: '', sampleRate: 0));
      final status = writer.onStatus.first;
      await expectLater(writer.startRecording(), throwsArgumentError);
      expect((await status).failureCode, reliability.ServiceFailureCode.invalidConfiguration);
      await writer.dispose();
    });

    test('queue overflow is observable and drops the rejected buffer', () async {
      final writer = LosslessRecordingWriter(config: RecordingConfig(destinationDirectory: directory.path, maxQueuedBytes: 1));
      final status = writer.onStatus.where((value) => value.failureCode == reliability.ServiceFailureCode.queueOverflow).first;
      await writer.startRecording();
      writer.writeStereoSamples(Float32List.fromList([0, 0]));
      expect((await status).state, reliability.ServiceOperationState.failed);
      final stats = await writer.stopRecording();
      expect(stats.droppedBuffers, 1);
      expect(stats.queuedBytes, 0);
      await writer.dispose();
    });
  });
}
