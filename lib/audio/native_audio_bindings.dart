/// Pure-Dart seam around the native LiveMixMaster C ABI.
///
/// The host orchestration uses this interface for non-real-time control and
/// compact status polling. Native audio callbacks never cross into Dart.
class NativeInputDevice {
  const NativeInputDevice({
    required this.objectId,
    required this.uid,
    required this.name,
    required this.inputChannels,
    required this.nominalSampleRate,
    required this.bufferFrames,
  });

  final int objectId;
  final String uid;
  final String name;
  final int inputChannels;
  final double nominalSampleRate;
  final int bufferFrames;
}

enum NativeCaptureState {
  idle,
  starting,
  running,
  deviceRemoved,
  formatChanged,
  failed,
}

class NativeCaptureStatus {
  const NativeCaptureStatus({
    required this.state,
    required this.sampleRate,
    required this.bufferFrames,
    required this.inputChannels,
    required this.formatFlags,
    required this.callbackCount,
    required this.xrunCount,
    required this.averageCallbackUs,
    required this.maxCallbackUs,
  });

  final NativeCaptureState state;
  final double sampleRate;
  final int bufferFrames;
  final int inputChannels;
  final int formatFlags;
  final int callbackCount;
  final int xrunCount;
  final double averageCallbackUs;
  final double maxCallbackUs;
}

class NativeChannelMeter {
  const NativeChannelMeter({
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

class NativeMasterMeter {
  const NativeMasterMeter({
    required this.truePeakLeft,
    required this.truePeakRight,
    required this.limiterActive,
  });

  final double truePeakLeft;
  final double truePeakRight;
  final bool limiterActive;
}

abstract interface class NativeAudioBindings {
  bool initialize(int sampleRate, int framesPerBuffer);
  List<NativeInputDevice> listInputDevices();

  bool addChannel(String id);
  bool removeChannel(String id);
  bool setFader(String id, double value);
  bool setMuted(String id, bool value);
  bool setSolo(String id, bool value);

  bool bindCaptureChannel(String id);
  bool captureStart(String uid, int channelPairIndex);
  void captureStop();
  NativeCaptureStatus captureStatus();

  NativeChannelMeter? channelMeter(String id);
  NativeMasterMeter? masterMeter();
}
