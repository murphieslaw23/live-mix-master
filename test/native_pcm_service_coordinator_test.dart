import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/native_audio_bindings.dart';
import 'package:live_mix_master/audio/native_pcm_service_coordinator.dart';
import 'package:live_mix_master/services/fingerprint_service.dart';
import 'package:live_mix_master/services/lossless_recording_writer.dart';

void main() {
  group('NativePcmServiceCoordinator', () {
    test('PCM consumers use negotiated 44100 Hz rate', () async {
      int? recordingRate;
      int? fingerprintRate;
      final coordinator = NativePcmServiceCoordinator(
        destinationDirectory: '/tmp/lmm-test',
        acoustIdApiKey: '',
        createRecordingConsumer: (config) {
          recordingRate = config.sampleRate;
          return _FakeRecordingConsumer();
        },
        createFingerprintConsumer: (config) async {
          fingerprintRate = config.sampleRate;
          return _FakeFingerprintConsumer();
        },
      );

      await coordinator.activateForCapture(
        _runningStatus(sampleRate: 44100),
      );

      expect(coordinator.sampleRate, 44100);
      expect(recordingRate, 44100);
      expect(fingerprintRate, 44100);

      await coordinator.dispose();
    });

    test('activation fails closed until negotiated capture is running', () async {
      final coordinator = NativePcmServiceCoordinator(
        destinationDirectory: '/tmp/lmm-test',
        acoustIdApiKey: '',
        createRecordingConsumer: (_) => _FakeRecordingConsumer(),
        createFingerprintConsumer: (_) async => _FakeFingerprintConsumer(),
      );

      await expectLater(
        coordinator.activateForCapture(
          _runningStatus(
            state: NativeCaptureState.starting,
            sampleRate: 44100,
          ),
        ),
        throwsStateError,
      );
      await expectLater(
        coordinator.activateForCapture(_runningStatus(sampleRate: 0)),
        throwsStateError,
      );
      expect(coordinator.sampleRate, isNull);

      await coordinator.dispose();
    });

    test('active recording blocks capture-rate reconfiguration', () async {
      final recorder = _FakeRecordingConsumer();
      final coordinator = NativePcmServiceCoordinator(
        destinationDirectory: '/tmp/lmm-test',
        acoustIdApiKey: '',
        createRecordingConsumer: (_) => recorder,
        createFingerprintConsumer: (_) async => _FakeFingerprintConsumer(),
      );

      await coordinator.activateForCapture(_runningStatus(sampleRate: 44100));
      await coordinator.startRecording();

      await expectLater(
        coordinator.activateForCapture(_runningStatus(sampleRate: 48000)),
        throwsStateError,
      );
      expect(coordinator.sampleRate, 44100);

      await coordinator.stopRecording();
      await coordinator.dispose();
    });
  });
}

NativeCaptureStatus _runningStatus({
  NativeCaptureState state = NativeCaptureState.running,
  required double sampleRate,
}) {
  return NativeCaptureStatus(
    state: state,
    sampleRate: sampleRate,
    bufferFrames: 256,
    inputChannels: 4,
    formatFlags: 0,
    callbackCount: 1,
    xrunCount: 0,
    averageCallbackUs: 100,
    maxCallbackUs: 150,
  );
}

class _FakeRecordingConsumer implements NativeRecordingConsumer {
  final StreamController<RecordingStats> _stats =
      StreamController<RecordingStats>.broadcast();
  bool _recording = false;

  @override
  bool get isRecording => _recording;

  @override
  Stream<RecordingStats> get onStatsUpdated => _stats.stream;

  @override
  Future<String> startRecording() async {
    _recording = true;
    return '/tmp/lmm-test.wav';
  }

  @override
  Future<RecordingStats> stopRecording() async {
    _recording = false;
    return const RecordingStats(
      totalBytesWritten: 44,
      elapsed: Duration.zero,
      filePath: '/tmp/lmm-test.wav',
      currentFileSizeMb: 0,
    );
  }

  @override
  void writeStereoSamples(Float32List samples) {}

  @override
  Future<void> dispose() => _stats.close();
}

class _FakeFingerprintConsumer implements NativeFingerprintConsumer {
  final StreamController<IdentifiedTrack> _tracks =
      StreamController<IdentifiedTrack>.broadcast();
  final StreamController<bool> _analyzing = StreamController<bool>.broadcast();

  @override
  Stream<IdentifiedTrack> get onTrackIdentified => _tracks.stream;

  @override
  Stream<bool> get onAnalyzingStatusChanged => _analyzing.stream;

  @override
  Future<void> start() async {}

  @override
  void pushPcmChunk(Float32List samples) {}

  @override
  Future<void> stop() async {
    await _tracks.close();
    await _analyzing.close();
  }
}
