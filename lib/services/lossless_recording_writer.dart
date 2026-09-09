import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'reliability_models.dart' as reliability;

enum PcmBitDepth {
  pcm16Bit(16, 2),
  pcm24Bit(24, 3),
  pcm32BitFloat(32, 4);
  const PcmBitDepth(this.bitDepth, this.bytesPerSample);
  final int bitDepth;
  final int bytesPerSample;
}

class RecordingConfig {
  const RecordingConfig({required this.destinationDirectory, this.sessionPrefix = 'LMM_SESSION', this.sampleRate = 48000, this.channels = 2, this.bitDepth = PcmBitDepth.pcm24Bit, this.flushThresholdBytes = 65536, this.maxQueuedBytes = 1048576});
  final String destinationDirectory;
  final String sessionPrefix;
  final int sampleRate;
  final int channels;
  final PcmBitDepth bitDepth;
  final int flushThresholdBytes;
  final int maxQueuedBytes;
  reliability.ServiceFailureCode? get validationFailure => destinationDirectory.trim().isEmpty || sampleRate <= 0 || channels <= 0 || flushThresholdBytes <= 0 || maxQueuedBytes <= 0 ? reliability.ServiceFailureCode.invalidConfiguration : null;
}

class RecordingStats {
  const RecordingStats({required this.totalBytesWritten, required this.elapsed, required this.filePath, required this.currentFileSizeMb, this.queuedBytes = 0, this.droppedBuffers = 0});
  final int totalBytesWritten;
  final Duration elapsed;
  final String filePath;
  final double currentFileSizeMb;
  final int queuedBytes;
  final int droppedBuffers;
}

class LosslessRecordingWriter {
  LosslessRecordingWriter({required this.config});
  final RecordingConfig config;
  final _events = StreamController<RecordingStats>.broadcast();
  final _statuses = StreamController<reliability.ServiceStatus>.broadcast();
  final _queue = <Uint8List>[];
  RandomAccessFile? _file;
  String? _path;
  DateTime? _started;
  Timer? _timer;
  Future<void>? _drainFuture;
  int _bytes = 0;
  int _queuedBytes = 0;
  int _droppedBuffers = 0;
  bool _accepting = false;
  bool _writeFailed = false;

  Stream<RecordingStats> get onStatsUpdated => _events.stream;
  Stream<reliability.ServiceStatus> get onStatus => _statuses.stream;
  bool get isRecording => _file != null && _accepting;
  String? get currentFilePath => _path;

  Future<String> startRecording() async {
    if (isRecording) throw StateError('Recording is already in progress.');
    final failure = config.validationFailure;
    if (failure != null) {
      _status(reliability.ServiceStatus.failed(failureCode: failure, message: 'Invalid recording configuration'));
      throw ArgumentError('Invalid recording configuration');
    }
    try {
      final dir = Directory(config.destinationDirectory);
      if (!await dir.exists()) await dir.create(recursive: true);
      _path = '${dir.path}/${config.sessionPrefix}_${DateTime.now().millisecondsSinceEpoch}.wav';
      _file = await File(_path!).open(mode: FileMode.write);
      _started = DateTime.now();
      _bytes = _queuedBytes = _droppedBuffers = 0;
      _writeFailed = false;
      _accepting = true;
      await _file!.writeFrom(_header(0));
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _emit());
      _status(const reliability.ServiceStatus.running());
      _emit();
      return _path!;
    } catch (_) {
      _accepting = false;
      _status(const reliability.ServiceStatus.failed(failureCode: reliability.ServiceFailureCode.writeFailed, message: 'Unable to open recording destination'));
      rethrow;
    }
  }

  void writeStereoSamples(Float32List samples) {
    if (!isRecording || _writeFailed) return;
    final bytes = _encode(samples);
    if (_queuedBytes + bytes.length > config.maxQueuedBytes) {
      _droppedBuffers++;
      _status(const reliability.ServiceStatus.failed(failureCode: reliability.ServiceFailureCode.queueOverflow, message: 'Recording queue capacity reached'));
      _emit();
      return;
    }
    _queue.add(bytes);
    _queuedBytes += bytes.length;
    _drainFuture ??= _drain();
  }

  Future<void> _drain() async {
    try {
      while (_queue.isNotEmpty && _file != null) {
        final bytes = _queue.removeAt(0);
        _queuedBytes -= bytes.length;
        await _file!.writeFrom(bytes);
        _bytes += bytes.length;
      }
    } catch (_) {
      _writeFailed = true;
      _status(const reliability.ServiceStatus.failed(failureCode: reliability.ServiceFailureCode.writeFailed, message: 'Recording write failed'));
    } finally {
      _drainFuture = null;
      if (_queue.isNotEmpty && !_writeFailed) _drainFuture = _drain();
    }
  }

  Future<RecordingStats> stopRecording() async {
    if (_file == null) throw StateError('Cannot stop a recording that is not active.');
    _accepting = false;
    _timer?.cancel();
    await (_drainFuture ?? Future<void>.value());
    try {
      if (_writeFailed) throw StateError('Recording write failed');
      await _file!.setPosition(0);
      await _file!.writeFrom(_header(_bytes));
      await _file!.flush();
      await _file!.close();
      _file = null;
      final stats = _stats();
      _started = null;
      _status(const reliability.ServiceStatus.succeeded());
      _emit(stats);
      return stats;
    } catch (_) {
      _status(const reliability.ServiceStatus.failed(failureCode: reliability.ServiceFailureCode.writeFailed, message: 'Recording finalization failed'));
      rethrow;
    }
  }

  Future<void> dispose() async {
    if (_file != null) await stopRecording();
    await _events.close();
    await _statuses.close();
  }

  RecordingStats _stats() => RecordingStats(totalBytesWritten: _bytes + 44, elapsed: _started == null ? Duration.zero : DateTime.now().difference(_started!), filePath: _path ?? '', currentFileSizeMb: (_bytes + 44) / 1048576, queuedBytes: _queuedBytes, droppedBuffers: _droppedBuffers);
  void _emit([RecordingStats? value]) { if (_path != null && !_events.isClosed) _events.add(value ?? _stats()); }
  void _status(reliability.ServiceStatus value) { if (!_statuses.isClosed) _statuses.add(value); }

  Uint8List _encode(Float32List input) {
    final out = Uint8List(input.length * config.bitDepth.bytesPerSample);
    final data = ByteData.sublistView(out);
    for (var i = 0; i < input.length; i++) {
      final value = input[i].clamp(-1.0, 1.0).toDouble();
      final offset = i * config.bitDepth.bytesPerSample;
      if (config.bitDepth == PcmBitDepth.pcm16Bit) data.setInt16(offset, (value * 32767).round(), Endian.little);
      else if (config.bitDepth == PcmBitDepth.pcm24Bit) { final sample = (value * 8388607).round(); out[offset] = sample & 255; out[offset + 1] = (sample >> 8) & 255; out[offset + 2] = (sample >> 16) & 255; }
      else data.setFloat32(offset, value, Endian.little);
    }
    return out;
  }

  Uint8List _header(int length) {
    final out = Uint8List(44);
    final data = ByteData.sublistView(out);
    out.setRange(0, 4, [82, 73, 70, 70]);
    data.setUint32(4, length + 36, Endian.little);
    out.setRange(8, 12, [87, 65, 86, 69]);
    out.setRange(12, 16, [102, 109, 116, 32]);
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, config.bitDepth == PcmBitDepth.pcm32BitFloat ? 3 : 1, Endian.little);
    data.setUint16(22, config.channels, Endian.little);
    data.setUint32(24, config.sampleRate, Endian.little);
    data.setUint32(28, config.sampleRate * config.channels * config.bitDepth.bytesPerSample, Endian.little);
    data.setUint16(32, config.channels * config.bitDepth.bytesPerSample, Endian.little);
    data.setUint16(34, config.bitDepth.bitDepth, Endian.little);
    out.setRange(36, 40, [100, 97, 116, 97]);
    data.setUint32(40, length, Endian.little);
    return out;
  }
}
