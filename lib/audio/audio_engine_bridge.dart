import 'dart:async';

enum AudioInputKind { hardware, applicationLoopback }

enum EngineState { idle, preparing, running, degraded, failed }

enum AudioRouteState {
  idle,
  preparing,
  active,
  noDevice,
  permissionDenied,
  noSignal,
  deviceLost,
  formatError,
  overrun,
  recovered,
  failed,
}

class AudioInputEndpoint {
  const AudioInputEndpoint({
    required this.uid,
    required this.name,
    required this.inputChannels,
    required this.nominalSampleRate,
    required this.bufferFrames,
  });

  final String uid;
  final String name;
  final int inputChannels;
  final double nominalSampleRate;
  final int bufferFrames;
}

class InputChannelConfig {
  const InputChannelConfig({
    required this.id,
    required this.name,
    required this.kind,
    required this.endpointId,
    this.trimDb = 0,
    this.fader = .8,
    this.muted = false,
    this.solo = false,
  });

  final String id;
  final String name;
  final AudioInputKind kind;
  final String endpointId;
  final double trimDb;
  final double fader;
  final bool muted;
  final bool solo;
}

class StereoMeter {
  const StereoMeter({
    required this.peakLeft,
    required this.peakRight,
    required this.rmsLeft,
    required this.rmsRight,
    required this.clipping,
  });

  final double peakLeft;
  final double peakRight;
  final double rmsLeft;
  final double rmsRight;
  final bool clipping;
}

class ChannelMeterSnapshot {
  const ChannelMeterSnapshot({required this.channelId, required this.meter});
  final String channelId;
  final StereoMeter meter;
}

class MasterMeterSnapshot {
  const MasterMeterSnapshot({
    required this.momentaryLufs,
    required this.shortTermLufs,
    required this.integratedLufs,
    required this.truePeakLeft,
    required this.truePeakRight,
    required this.limiterActive,
  });

  final double momentaryLufs;
  final double shortTermLufs;
  final double integratedLufs;
  final double truePeakLeft;
  final double truePeakRight;
  final bool limiterActive;
}

class TrackMatch {
  const TrackMatch({
    required this.artist,
    required this.title,
    required this.confidence,
    required this.detectedAt,
    this.release,
  });

  final String artist;
  final String title;
  final String? release;
  final double confidence;
  final DateTime detectedAt;
}

abstract interface class AudioEngine {
  EngineState get state;
  AudioRouteState get routeState;
  Stream<AudioRouteState> get routeStates;
  Stream<List<ChannelMeterSnapshot>> get channelMeters;
  Stream<MasterMeterSnapshot> get masterMeters;
  Stream<TrackMatch> get trackMatches;

  Future<void> initialize({int sampleRate = 48000, int framesPerBuffer = 256});
  Future<List<AudioInputEndpoint>> refreshInputDevices();
  Future<void> addChannel(InputChannelConfig channel);
  Future<void> removeChannel(String channelId);
  Future<void> setTrim(String channelId, double db);
  Future<void> setFader(String channelId, double value);
  Future<void> setMute(String channelId, bool value);
  Future<void> setSolo(String channelId, bool value);
  Future<void> setMasterGain(double db);
  Future<void> startRecording(String filePath);
  Future<void> stopRecording();
  Future<void> startBroadcast(BroadcastTarget target);
  Future<void> stopBroadcast();
  Future<void> dispose();
}

class BroadcastTarget {
  const BroadcastTarget({required this.kind, required this.endpoint});
  final String kind;
  final Uri endpoint;
}
