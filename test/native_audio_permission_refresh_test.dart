import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/audio_engine_bridge.dart';
import 'package:live_mix_master/audio/audio_permission_state.dart';
import 'package:live_mix_master/audio/native_audio_bindings.dart';
import 'package:live_mix_master/audio/native_audio_engine.dart';

void main() {
  test('refresh re-reads permission after System Settings changes it', () async {
    var permission = AudioPermissionState.denied;
    final bindings = _PermissionRefreshBindings();
    final engine = NativeAudioEngine(
      bindings: bindings,
      permissionState: permission,
      permissionStateProvider: () => permission,
      pollInterval: null,
    );

    await engine.initialize();
    expect(await engine.refreshInputDevices(), isEmpty);
    expect(engine.routeState, AudioRouteState.permissionDenied);

    permission = AudioPermissionState.granted;
    final inputs = await engine.refreshInputDevices();
    expect(inputs.single.uid, 'coreaudio:permission-refresh');

    await engine.addChannel(
      const InputChannelConfig(
        id: 'permission-refresh-channel',
        name: 'PERMISSION REFRESH',
        kind: AudioInputKind.hardware,
        endpointId: 'coreaudio:permission-refresh',
      ),
    );
    expect(bindings.captureStarts, 1);

    await engine.dispose();
  });
}

class _PermissionRefreshBindings implements NativeAudioBindings {
  int captureStarts = 0;
  var captureRunning = false;

  @override
  bool initialize(int sampleRate, int framesPerBuffer) => true;

  @override
  List<NativeInputDevice> listInputDevices() => const <NativeInputDevice>[
        NativeInputDevice(
          objectId: 23,
          uid: 'coreaudio:permission-refresh',
          name: 'Permission Refresh Input',
          inputChannels: 2,
          nominalSampleRate: 44100,
          bufferFrames: 256,
        ),
      ];

  @override
  bool addChannel(String id) => true;

  @override
  bool removeChannel(String id) => true;

  @override
  bool setFader(String id, double value) => true;

  @override
  bool setMuted(String id, bool value) => true;

  @override
  bool setSolo(String id, bool value) => true;

  @override
  bool bindCaptureChannel(String id) => true;

  @override
  bool captureStart(String uid, int channelPairIndex) {
    captureStarts += 1;
    captureRunning = true;
    return true;
  }

  @override
  void captureStop() {
    captureRunning = false;
  }

  @override
  NativeCaptureStatus captureStatus() => NativeCaptureStatus(
        state: captureRunning
            ? NativeCaptureState.running
            : NativeCaptureState.idle,
        sampleRate: captureRunning ? 44100 : 0,
        bufferFrames: captureRunning ? 256 : 0,
        inputChannels: captureRunning ? 2 : 0,
        formatFlags: 0,
        callbackCount: 0,
        xrunCount: 0,
        averageCallbackUs: 0,
        maxCallbackUs: 0,
      );

  @override
  NativeChannelMeter? channelMeter(String id) => null;

  @override
  NativeMasterMeter? masterMeter() => null;
}
