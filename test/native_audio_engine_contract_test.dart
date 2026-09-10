import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/audio_engine_bridge.dart';
import 'package:live_mix_master/audio/audio_permission_state.dart';
import 'package:live_mix_master/audio/native_audio_bindings.dart';
import 'package:live_mix_master/audio/native_audio_engine.dart';

void main() {
  group('NativeAudioEngine host adapter contract', () {
    test('discovers stable UIDs and binds the selected endpoint to a mixer channel', () async {
      final bindings = _FakeNativeAudioBindings(
        devices: const [
          NativeInputDevice(
            objectId: 42,
            uid: 'coreaudio:usb-line-in',
            name: 'USB Line In',
            inputChannels: 2,
            nominalSampleRate: 48000,
            bufferFrames: 256,
          ),
        ],
      );
      final engine = NativeAudioEngine(
        bindings: bindings,
        permissionState: AudioPermissionState.granted,
        pollInterval: null,
      );

      await engine.initialize(sampleRate: 48000, framesPerBuffer: 256);
      final inputs = await engine.refreshInputDevices();

      expect(inputs, hasLength(1));
      expect(inputs.single.uid, 'coreaudio:usb-line-in');
      expect(inputs.single.name, 'USB Line In');
      expect(inputs.single.inputChannels, 2);
      expect(inputs.single.nominalSampleRate, 48000);
      expect(inputs.single.bufferFrames, 256);

      await engine.addChannel(
        const InputChannelConfig(
          id: 'capture-1',
          name: 'USB 1-2',
          kind: AudioInputKind.hardware,
          endpointId: 'coreaudio:usb-line-in',
          fader: .5,
          muted: true,
          solo: false,
        ),
      );

      expect(
        bindings.calls,
        containsAllInOrder(<String>[
          'init:48000:256',
          'listInputDevices',
          'addChannel:capture-1',
          'setFader:capture-1:0.5',
          'setMuted:capture-1:true',
          'setSolo:capture-1:false',
          'bindCaptureChannel:capture-1',
          'captureStart:coreaudio:usb-line-in',
        ]),
      );

      bindings.status = const NativeCaptureStatus(
        state: NativeCaptureState.running,
        sampleRate: 48000,
        bufferFrames: 256,
        inputChannels: 2,
        formatFlags: 0x29,
        callbackCount: 1,
        xrunCount: 0,
        averageCallbackUs: 90,
        maxCallbackUs: 120,
      );
      await engine.pollNow();

      expect(engine.state, EngineState.running);
      expect(engine.routeState, AudioRouteState.active);
      expect(engine.captureStatus?.callbackCount, 1);

      await engine.dispose();
      expect(bindings.calls.last, 'captureStop');
    });

    test('keeps permission denial and no-device discovery distinct', () async {
      final deniedBindings = _FakeNativeAudioBindings();
      final deniedEngine = NativeAudioEngine(
        bindings: deniedBindings,
        permissionState: AudioPermissionState.denied,
        pollInterval: null,
      );
      await deniedEngine.initialize();

      expect(deniedEngine.routeState, AudioRouteState.permissionDenied);
      await expectLater(
        deniedEngine.addChannel(
          const InputChannelConfig(
            id: 'blocked',
            name: 'Blocked input',
            kind: AudioInputKind.hardware,
            endpointId: 'coreaudio:blocked',
          ),
        ),
        throwsStateError,
      );
      expect(
        deniedBindings.calls.where((call) => call.startsWith('captureStart:')),
        isEmpty,
      );

      final emptyBindings = _FakeNativeAudioBindings();
      final emptyEngine = NativeAudioEngine(
        bindings: emptyBindings,
        permissionState: AudioPermissionState.granted,
        pollInterval: null,
      );
      await emptyEngine.initialize();
      expect(await emptyEngine.refreshInputDevices(), isEmpty);
      expect(emptyEngine.routeState, AudioRouteState.noDevice);

      await deniedEngine.dispose();
      await emptyEngine.dispose();
    });

    test('maps lost format no-signal overrun and recovery without callback crossing', () async {
      final bindings = _FakeNativeAudioBindings(
        devices: const [
          NativeInputDevice(
            objectId: 7,
            uid: 'coreaudio:test',
            name: 'Test Input',
            inputChannels: 2,
            nominalSampleRate: 44100,
            bufferFrames: 128,
          ),
        ],
      );
      final engine = NativeAudioEngine(
        bindings: bindings,
        permissionState: AudioPermissionState.granted,
        pollInterval: null,
        noSignalPollThreshold: 2,
      );
      await engine.initialize(sampleRate: 44100, framesPerBuffer: 128);
      await engine.refreshInputDevices();
      await engine.addChannel(
        const InputChannelConfig(
          id: 'capture-test',
          name: 'TEST',
          kind: AudioInputKind.hardware,
          endpointId: 'coreaudio:test',
          fader: 1,
        ),
      );

      bindings.status = _status(
        NativeCaptureState.running,
        callbacks: 10,
      );
      await engine.pollNow();
      expect(engine.routeState, AudioRouteState.active);

      await engine.pollNow();
      expect(engine.routeState, AudioRouteState.active);
      await engine.pollNow();
      expect(engine.routeState, AudioRouteState.noSignal);
      expect(engine.state, EngineState.degraded);

      bindings.status = _status(
        NativeCaptureState.running,
        callbacks: 11,
      );
      await engine.pollNow();
      expect(engine.routeState, AudioRouteState.recovered);
      await engine.pollNow();
      expect(engine.routeState, AudioRouteState.noSignal);

      bindings.status = _status(
        NativeCaptureState.deviceRemoved,
        callbacks: 11,
      );
      await engine.pollNow();
      expect(engine.routeState, AudioRouteState.deviceLost);

      bindings.status = _status(
        NativeCaptureState.running,
        callbacks: 12,
      );
      await engine.pollNow();
      expect(engine.routeState, AudioRouteState.recovered);

      bindings.status = _status(
        NativeCaptureState.formatChanged,
        callbacks: 12,
      );
      await engine.pollNow();
      expect(engine.routeState, AudioRouteState.formatError);

      bindings.status = _status(
        NativeCaptureState.running,
        callbacks: 13,
      );
      await engine.pollNow();
      expect(engine.routeState, AudioRouteState.recovered);

      bindings.status = _status(
        NativeCaptureState.running,
        callbacks: 14,
        xruns: 1,
      );
      await engine.pollNow();
      expect(engine.routeState, AudioRouteState.overrun);
      expect(engine.state, EngineState.degraded);

      bindings.status = _status(
        NativeCaptureState.running,
        callbacks: 15,
        xruns: 1,
      );
      await engine.pollNow();
      expect(engine.routeState, AudioRouteState.recovered);

      await engine.dispose();
    });
  });
}

NativeCaptureStatus _status(
  NativeCaptureState state, {
  required int callbacks,
  int xruns = 0,
}) =>
    NativeCaptureStatus(
      state: state,
      sampleRate: 48000,
      bufferFrames: 256,
      inputChannels: 2,
      formatFlags: 0x29,
      callbackCount: callbacks,
      xrunCount: xruns,
      averageCallbackUs: 100,
      maxCallbackUs: 150,
    );

class _FakeNativeAudioBindings implements NativeAudioBindings {
  _FakeNativeAudioBindings({this.devices = const <NativeInputDevice>[]});

  final List<NativeInputDevice> devices;
  final List<String> calls = <String>[];
  NativeCaptureStatus status = const NativeCaptureStatus(
    state: NativeCaptureState.idle,
    sampleRate: 0,
    bufferFrames: 0,
    inputChannels: 0,
    formatFlags: 0,
    callbackCount: 0,
    xrunCount: 0,
    averageCallbackUs: 0,
    maxCallbackUs: 0,
  );

  @override
  bool initialize(int sampleRate, int framesPerBuffer) {
    calls.add('init:$sampleRate:$framesPerBuffer');
    return true;
  }

  @override
  List<NativeInputDevice> listInputDevices() {
    calls.add('listInputDevices');
    return devices;
  }

  @override
  bool addChannel(String id) {
    calls.add('addChannel:$id');
    return true;
  }

  @override
  bool removeChannel(String id) {
    calls.add('removeChannel:$id');
    return true;
  }

  @override
  bool setFader(String id, double value) {
    calls.add('setFader:$id:$value');
    return true;
  }

  @override
  bool setMuted(String id, bool value) {
    calls.add('setMuted:$id:$value');
    return true;
  }

  @override
  bool setSolo(String id, bool value) {
    calls.add('setSolo:$id:$value');
    return true;
  }

  @override
  bool bindCaptureChannel(String id) {
    calls.add('bindCaptureChannel:$id');
    return true;
  }

  @override
  bool captureStart(String uid) {
    calls.add('captureStart:$uid');
    return true;
  }

  @override
  void captureStop() {
    calls.add('captureStop');
  }

  @override
  NativeCaptureStatus captureStatus() => status;

  @override
  NativeChannelMeter? channelMeter(String id) => null;

  @override
  NativeMasterMeter? masterMeter() => null;
}
