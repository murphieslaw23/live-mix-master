import 'dart:async';
import 'dart:typed_data';

import '../services/fingerprint_service.dart';
import '../services/lossless_recording_writer.dart';
import '../services/mixer_service_ports.dart';
import 'native_audio_bindings.dart';

abstract interface class NativeRecordingConsumer implements MixerRecordingPort {
  bool get isRecording;
  void writeStereoSamples(Float32List samples);
  Future<void> dispose();
}

abstract interface class NativeFingerprintConsumer implements MixerFingerprintPort {
  Future<void> start();
  void pushPcmChunk(Float32List samples);
  Future<void> stop();
}

typedef NativeRecordingConsumerFactory = NativeRecordingConsumer Function(
  RecordingConfig config,
);
typedef NativeFingerprintConsumerFactory = Future<NativeFingerprintConsumer>
    Function(AudioFingerprintConfig config);

/// Owns replaceable recorder/fingerprint implementations while exposing stable
/// stream objects to the mixer for the lifetime of the desktop runtime.
///
/// Activation is allowed only after Core Audio reports a running negotiated
/// format. No default sample rate is used as authoritative capture metadata.
class NativePcmServiceCoordinator
    implements MixerRecordingPort, MixerFingerprintPort {
  NativePcmServiceCoordinator({
    required this.destinationDirectory,
    required this.acoustIdApiKey,
    NativeRecordingConsumerFactory? createRecordingConsumer,
    NativeFingerprintConsumerFactory? createFingerprintConsumer,
  })  : _createRecordingConsumer =
            createRecordingConsumer ?? _defaultRecordingConsumer,
        _createFingerprintConsumer =
            createFingerprintConsumer ?? _defaultFingerprintConsumer;

  final String destinationDirectory;
  final String acoustIdApiKey;
  final NativeRecordingConsumerFactory _createRecordingConsumer;
  final NativeFingerprintConsumerFactory _createFingerprintConsumer;

  final StreamController<RecordingStats> _recordingStats =
      StreamController<RecordingStats>.broadcast();
  final StreamController<IdentifiedTrack> _tracks =
      StreamController<IdentifiedTrack>.broadcast();
  final StreamController<bool> _analyzing =
      StreamController<bool>.broadcast();

  NativeRecordingConsumer? _recordingConsumer;
  NativeFingerprintConsumer? _fingerprintConsumer;
  StreamSubscription<RecordingStats>? _recordingStatsSubscription;
  StreamSubscription<IdentifiedTrack>? _trackSubscription;
  StreamSubscription<bool>? _analyzingSubscription;
  int? _sampleRate;
  bool _disposed = false;

  int? get sampleRate => _sampleRate;
  bool get isRecording => _recordingConsumer?.isRecording ?? false;

  @override
  Stream<RecordingStats> get onStatsUpdated => _recordingStats.stream;

  @override
  Stream<IdentifiedTrack> get onTrackIdentified => _tracks.stream;

  @override
  Stream<bool> get onAnalyzingStatusChanged => _analyzing.stream;

  Future<void> activateForCapture(NativeCaptureStatus status) async {
    _ensureUsable();
    final rate = status.sampleRate.round();
    if (status.state != NativeCaptureState.running || rate <= 0) {
      throw StateError('Capture format is not ready for PCM consumers.');
    }
    if (isRecording) {
      throw StateError(
        'Cannot change PCM consumer format while recording is active.',
      );
    }

    await _tearDownConsumers();

    NativeRecordingConsumer? recording;
    NativeFingerprintConsumer? fingerprint;
    try {
      recording = _createRecordingConsumer(
        RecordingConfig(
          destinationDirectory: destinationDirectory,
          sampleRate: rate,
          channels: 2,
        ),
      );
      fingerprint = await _createFingerprintConsumer(
        AudioFingerprintConfig(
          acoustIdApiKey: acoustIdApiKey,
          sampleRate: rate,
          channels: 2,
        ),
      );
      await fingerprint.start();

      _recordingConsumer = recording;
      _fingerprintConsumer = fingerprint;
      _sampleRate = rate;
      _recordingStatsSubscription = recording.onStatsUpdated.listen(
        _recordingStats.add,
      );
      _trackSubscription = fingerprint.onTrackIdentified.listen(_tracks.add);
      _analyzingSubscription = fingerprint.onAnalyzingStatusChanged.listen(
        _analyzing.add,
      );
    } catch (_) {
      _sampleRate = null;
      if (recording != null) {
        await recording.dispose();
      }
      if (fingerprint != null) {
        await fingerprint.stop();
      }
      rethrow;
    }
  }

  @override
  Future<String> startRecording() {
    _ensureUsable();
    final recording = _recordingConsumer;
    if (recording == null) {
      return Future<String>.error(
        StateError('PCM services are not activated for a negotiated capture.'),
      );
    }
    return recording.startRecording();
  }

  @override
  Future<RecordingStats> stopRecording() {
    _ensureUsable();
    final recording = _recordingConsumer;
    if (recording == null) {
      return Future<RecordingStats>.error(
        StateError('PCM services are not activated for a negotiated capture.'),
      );
    }
    return recording.stopRecording();
  }

  void pushRecordingPcm(Float32List samples) {
    if (_disposed) return;
    _recordingConsumer?.writeStereoSamples(samples);
  }

  void pushFingerprintPcm(Float32List samples) {
    if (_disposed) return;
    _fingerprintConsumer?.pushPcmChunk(samples);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _tearDownConsumers();
    await _recordingStats.close();
    await _tracks.close();
    await _analyzing.close();
  }

  Future<void> _tearDownConsumers() async {
    await _recordingStatsSubscription?.cancel();
    await _trackSubscription?.cancel();
    await _analyzingSubscription?.cancel();
    _recordingStatsSubscription = null;
    _trackSubscription = null;
    _analyzingSubscription = null;

    final recording = _recordingConsumer;
    final fingerprint = _fingerprintConsumer;
    _recordingConsumer = null;
    _fingerprintConsumer = null;
    _sampleRate = null;

    if (recording != null) {
      await recording.dispose();
    }
    if (fingerprint != null) {
      await fingerprint.stop();
    }
  }

  void _ensureUsable() {
    if (_disposed) {
      throw StateError('NativePcmServiceCoordinator has already been disposed.');
    }
  }

  static NativeRecordingConsumer _defaultRecordingConsumer(
    RecordingConfig config,
  ) {
    return _LosslessRecordingConsumer(
      LosslessRecordingWriter(config: config),
    );
  }

  static Future<NativeFingerprintConsumer> _defaultFingerprintConsumer(
    AudioFingerprintConfig config,
  ) async {
    return _FingerprintServiceConsumer(FingerprintService(config: config));
  }
}

class _LosslessRecordingConsumer implements NativeRecordingConsumer {
  _LosslessRecordingConsumer(this.writer);

  final LosslessRecordingWriter writer;

  @override
  bool get isRecording => writer.isRecording;

  @override
  Stream<RecordingStats> get onStatsUpdated => writer.onStatsUpdated;

  @override
  Future<String> startRecording() => writer.startRecording();

  @override
  Future<RecordingStats> stopRecording() => writer.stopRecording();

  @override
  void writeStereoSamples(Float32List samples) {
    writer.writeStereoSamples(samples);
  }

  @override
  Future<void> dispose() => writer.dispose();
}

class _FingerprintServiceConsumer implements NativeFingerprintConsumer {
  _FingerprintServiceConsumer(this.service);

  final FingerprintService service;

  @override
  Stream<IdentifiedTrack> get onTrackIdentified => service.onTrackIdentified;

  @override
  Stream<bool> get onAnalyzingStatusChanged =>
      service.onAnalyzingStatusChanged;

  @override
  Future<void> start() => service.start();

  @override
  void pushPcmChunk(Float32List samples) => service.pushPcmChunk(samples);

  @override
  Future<void> stop() => service.stop();
}
