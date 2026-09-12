import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/audio_engine_bridge.dart';
import 'package:live_mix_master/audio/audio_permission_state.dart';
import 'package:live_mix_master/audio/native_audio_bindings.dart';
import 'package:live_mix_master/audio/native_audio_engine.dart';

void main() {
  test('selected channel pair is forwarded to native capture', () async {
    final bindings = _RouteBindings();
    final engine = NativeAudioEngine(
      bindings: bindings,
      permissionState: AudioPermissionState.granted,
      pollInterval: null,
    );

    await engine.initialize();
    await engine.refreshInputDevices();
    await engine.addChannel(
      const InputChannelConfig(
        id: 'deck-b',
        name: 'DECK B',
        kind: AudioInputKind.hardware,
        endpointId: 'device-1',
        channelPairIndex: 1,
      ),
    );

    expect(bindings.captureStarts, [('device-1', 1)]);
  });

  test('second native route is rejected without rebinding capture', () async {
    final bindings = _RouteBindings();
    final engine = NativeAudioEngine(
      bindings: bindings,
      permissionState: AudioPermissionState.granted,
      pollInterval: null,
    );

    await engine.initialize();
    await engine.refreshInputDevices();
    await engine.addChannel(
      const InputChannelConfig(
        id: 'deck-a',
        name: 'DECK A',
        kind: AudioInputKind.hardware,
        endpointId: 'device-1',
      ),
    );

    await expectLater(
      engine.addChannel(
        const InputChannelConfig(
          id: 'deck-b',
          name: 'DECK B',
          kind: AudioInputKind.hardware,
          endpointId: 'device-1',
          channelPairIndex: 1,
        ),
      ),
      throwsStateError,
    );

    expect(bindings.captureStarts, [('device-1', 0)]);
  });
}

class _RouteBindings implements NativeAudioBindings {
  final List<(String, int)> captureStarts = [];

  @override
  bool initialize(int sampleRate, int framesPerBuffer) => true;

  @override
  List<NativeInputDevice> listInputDevices() => const [
        NativeInputDevice(
          objectId: 1,
          uid: 'device-1',
          name: 'Four Channel Interface',
          inputChannels: 4,
          nominalSampleRate: 48000,
          bufferFrames: 128,
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
    captureStarts.add((uid, channelPairIndex));
    return true;
  }

  @override
  void captureStop() {}

  @override
  NativeCaptureStatus captureStatus() => const NativeCaptureStatus(
        state: NativeCaptureState.running,
        sampleRate: 48000,
        bufferFrames: 128,
        inputChannels: 4,
        formatFlags: 0,
        callbackCount: 1,
        xrunCount: 0,
        averageCallbackUs: 10,
        maxCallbackUs: 10,
      );

  @override
  NativeChannelMeter? channelMeter(String id) => null;

  @override
  NativeMasterMeter? masterMeter() => null;
}
