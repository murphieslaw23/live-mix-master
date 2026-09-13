import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/audio_engine_bridge.dart';
import 'package:live_mix_master/audio/audio_permission_state.dart';
import 'package:live_mix_master/audio/native_audio_bindings.dart';
import 'package:live_mix_master/audio/native_audio_engine.dart';
import 'package:live_mix_master/audio/native_audio_gain_bindings.dart';

void main() {
  test('initial trim is applied before capture starts and direct controls reach bindings', () async {
    final bindings = _ControlBindings();
    final engine = NativeAudioEngine(
      bindings: bindings,
      gainBindings: bindings,
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
        trimDb: -3,
      ),
    );

    expect(bindings.events, containsAllInOrder([
      'add:deck-a',
      'trim:deck-a:-3.0',
      'fader:deck-a:0.8',
      'bind:deck-a',
      'capture:device-1:0',
    ]));

    await engine.setTrim('deck-a', -6);
    await engine.setMasterGain(-4.5);

    expect(bindings.events, contains('trim:deck-a:-6.0'));
    expect(bindings.events, contains('master:-4.5'));
  });
}

class _ControlBindings implements NativeAudioBindings, NativeAudioGainBindings {
  final events = <String>[];

  @override
  bool initialize(int sampleRate, int framesPerBuffer) => true;

  @override
  List<NativeInputDevice> listInputDevices() => const [
        NativeInputDevice(
          objectId: 1,
          uid: 'device-1',
          name: 'Device',
          inputChannels: 2,
          nominalSampleRate: 48000,
          bufferFrames: 128,
        ),
      ];

  @override
  bool addChannel(String id) {
    events.add('add:$id');
    return true;
  }

  @override
  bool removeChannel(String id) => true;

  @override
  bool setTrim(String id, double db) {
    events.add('trim:$id:$db');
    return true;
  }

  @override
  bool setFader(String id, double value) {
    events.add('fader:$id:$value');
    return true;
  }

  @override
  bool setMuted(String id, bool value) => true;

  @override
  bool setSolo(String id, bool value) => true;

  @override
  bool setMasterGain(double db) {
    events.add('master:$db');
    return true;
  }

  @override
  bool bindCaptureChannel(String id) {
    events.add('bind:$id');
    return true;
  }

  @override
  bool captureStart(String uid, int channelPairIndex) {
    events.add('capture:$uid:$channelPairIndex');
    return true;
  }

  @override
  void captureStop() {}

  @override
  NativeCaptureStatus captureStatus() => const NativeCaptureStatus(
        state: NativeCaptureState.running,
        sampleRate: 48000,
        bufferFrames: 128,
        inputChannels: 2,
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
