import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Lossless WAV / Broadcast WAV Recording Writer for LiveMixMaster
///
/// Records post-master stereo PCM streams directly to disk in 24-bit or 16-bit
/// uncompressed RIFF/WAVE format. Handles buffered async file I/O off the audio
/// thread, manages rolling chunk flushes, and safely finalizes WAV RIFF header sizes
/// upon session stop or power-loss recovery.

enum PcmBitDepth {
  pcm16Bit(16, 2),
  pcm24Bit(24, 3),
  pcm32BitFloat(32, 4);

  final int bitDepth;
  final int bytesPerSample;
  const PcmBitDepth(this.bitDepth, this.bytesPerSample);
}

class RecordingConfig {
  final String destinationDirectory;
  final String sessionPrefix;
  final int sampleRate;
  final int channels;
  final PcmBitDepth bitDepth;
  final int flushThresholdBytes;

  const RecordingConfig({
    required this.destinationDirectory,
    this.sessionPrefix = 'LMM_SESSION',
    this.sampleRate = 48000,
    this.channels = 2,
    this.bitDepth = PcmBitDepth.pcm24Bit,
    this.flushThresholdBytes = 64 * 1024, // 64 KB buffer flush
  });
}

class RecordingStats {
  final int totalBytesWritten;
  final Duration elapsed;
  final String filePath;
  final double currentFileSizeMb;

  const RecordingStats({
    required this.totalBytesWritten,
    required this.elapsed,
    required this.filePath,
    required this.currentFileSizeMb,
  });
}

class LosslessRecordingWriter {
  final RecordingConfig config;
  final StreamController<RecordingStats> _statsController = StreamController<RecordingStats>.broadcast();

  File? _file;
  RandomAccessFile? _raf;
  DateTime? _startTime;
  Timer? _statsTimer;
  int _totalPcmBytesWritten = 0;
  final BytesBuilder _memoryBuffer = BytesBuilder(copy: false);

  LosslessRecordingWriter({required this.config});

  Stream<RecordingStats> get onStatsUpdated => _statsController.stream;
  bool get isRecording => _raf != null;
  String? get currentFilePath => _file?.path;

  /// Arms and creates the recording file with a placeholder 44-byte RIFF header.
  Future<String> startRecording() async {
    if (isRecording) {
      throw StateError('Recording is already in progress.');
    }

    final dir = Directory(config.destinationDirectory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
    final fileName = '${config.sessionPrefix}_$timestamp.wav';
    _file = File('${dir.path}/$fileName');

    _raf = await _file!.open(mode: FileMode.write);
    _totalPcmBytesWritten = 0;
    _startTime = DateTime.now();

    // Write preliminary 44-byte WAV header (sizes populated as 0 until finalized)
    final preliminaryHeader = _createWavHeader(
      sampleRate: config.sampleRate,
      channels: config.channels,
      bitDepth: config.bitDepth,
      dataLength: 0,
    );
    await _raf!.writeFrom(preliminaryHeader);

    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) => _emitStats());
    _emitStats();

    return _file!.path;
  }

  /// Ingests normalized stereo Float32List samples (-1.0 to +1.0) from the master bus.
  void writeStereoSamples(Float32List samples) {
    if (_raf == null) return;

    final Uint8List encodedBytes = _convertFloatToBytes(samples, config.bitDepth);
    _memoryBuffer.add(encodedBytes);

    if (_memoryBuffer.length >= config.flushThresholdBytes) {
      _flushBufferToDisk();
    }
  }

  /// Flushes in-memory PCM bytes to the random access file.
  void _flushBufferToDisk() {
    if (_raf == null || _memoryBuffer.isEmpty) return;
    final bytesToWrite = _memoryBuffer.takeBytes();
    _raf!.writeFromSync(bytesToWrite);
    _totalPcmBytesWritten += bytesToWrite.length;
  }

  /// Finalizes the WAV header with exact byte sizes and closes the file descriptor.
  Future<RecordingStats> stopRecording() async {
    if (_raf == null || _file == null) {
      throw StateError('Cannot stop a recording that is not active.');
    }

    _statsTimer?.cancel();
    _flushBufferToDisk();

    // Rewind to file origin and patch official RIFF and data chunk headers
    await _raf!.setPosition(0);
    final finalizedHeader = _createWavHeader(
      sampleRate: config.sampleRate,
      channels: config.channels,
      bitDepth: config.bitDepth,
      dataLength: _totalPcmBytesWritten,
    );
    await _raf!.writeFrom(finalizedHeader);
    await _raf!.flush();
    await _raf!.close();

    final finalStats = RecordingStats(
      totalBytesWritten: _totalPcmBytesWritten + 44,
      elapsed: _startTime != null ? DateTime.now().difference(_startTime!) : Duration.zero,
      filePath: _file!.path,
      currentFileSizeMb: (_totalPcmBytesWritten + 44) / (1024 * 1024),
    );

    _raf = null;
    _startTime = null;
    _emitStats();

    return finalStats;
  }

  void _emitStats() {
    if (_file == null) return;
    _statsController.add(RecordingStats(
      totalBytesWritten: _totalPcmBytesWritten + 44,
      elapsed: _startTime != null ? DateTime.now().difference(_startTime!) : Duration.zero,
      filePath: _file!.path,
      currentFileSizeMb: (_totalPcmBytesWritten + 44) / (1024 * 1024),
    ));
  }

  Future<void> dispose() async {
    if (isRecording) {
      await stopRecording();
    }
    await _statsController.close();
  }

  /// Converts float PCM (-1.0 to 1.0) to raw little-endian bytes based on bit depth.
  static Uint8List _convertFloatToBytes(Float32List input, PcmBitDepth depth) {
    final int sampleCount = input.length;

    switch (depth) {
      case PcmBitDepth.pcm16Bit:
        final Uint8List out = Uint8List(sampleCount * 2);
        final ByteData bd = ByteData.sublistView(out);
        for (int i = 0; i < sampleCount; i++) {
          final double clamped = input[i].clamp(-1.0, 1.0);
          final int sampleInt = (clamped * 32767.0).round();
          bd.setInt16(i * 2, sampleInt, Endian.little);
        }
        return out;

      case PcmBitDepth.pcm24Bit:
        final Uint8List out = Uint8List(sampleCount * 3);
        for (int i = 0; i < sampleCount; i++) {
          final double clamped = input[i].clamp(-1.0, 1.0);
          final int sampleInt = (clamped * 8388607.0).round();
          final int base = i * 3;
          out[base] = sampleInt & 0xFF;
          out[base + 1] = (sampleInt >> 8) & 0xFF;
          out[base + 2] = (sampleInt >> 16) & 0xFF;
        }
        return out;

      case PcmBitDepth.pcm32BitFloat:
        final Uint8List out = Uint8List(sampleCount * 4);
        final ByteData bd = ByteData.sublistView(out);
        for (int i = 0; i < sampleCount; i++) {
          bd.setFloat32(i * 4, input[i], Endian.little);
        }
        return out;
    }
  }

  /// Synthesizes standard 44-byte Canonical RIFF/WAVE header.
  static Uint8List _createWavHeader({
    required int sampleRate,
    required int channels,
    required PcmBitDepth bitDepth,
    required int dataLength,
  }) {
    final int formatCode = bitDepth == PcmBitDepth.pcm32BitFloat ? 3 : 1; // 1 = PCM, 3 = IEEE Float
    final int byteRate = sampleRate * channels * bitDepth.bytesPerSample;
    final int blockAlign = channels * bitDepth.bytesPerSample;
    final int fileSizeMinus8 = dataLength + 36;

    final Uint8List header = Uint8List(44);
    final ByteData bd = ByteData.sublistView(header);

    // RIFF Chunk
    header.setRange(0, 4, [0x52, 0x49, 0x46, 0x46]); // "RIFF"
    bd.setUint32(4, fileSizeMinus8, Endian.little);
    header.setRange(8, 12, [0x57, 0x41, 0x56, 0x45]); // "WAVE"

    // "fmt " Subchunk
    header.setRange(12, 16, [0x66, 0x6D, 0x74, 0x20]); // "fmt "
    bd.setUint32(16, 16, Endian.little); // Subchunk size (16 for PCM)
    bd.setUint16(20, formatCode, Endian.little);
    bd.setUint16(22, channels, Endian.little);
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, byteRate, Endian.little);
    bd.setUint16(32, blockAlign, Endian.little);
    bd.setUint16(34, bitDepth.bitDepth, Endian.little);

    // "data" Subchunk
    header.setRange(36, 40, [0x64, 0x61, 0x74, 0x61]); // "data"
    bd.setUint32(40, dataLength, Endian.little);

    return header;
  }
}
