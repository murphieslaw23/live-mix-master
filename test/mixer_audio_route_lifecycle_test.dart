import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/audio_engine_bridge.dart';
import 'package:live_mix_master/features/mixer/mixer_desk_view.dart';

void main() {
  testWidgets(
    'mixer surfaces engine route lifecycle and recovery opens live endpoint patchbay',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final engine = _FakeAudioEngine(
        inputs: const <AudioInputEndpoint>[
          AudioInputEndpoint(
            uid: 'coreaudio:usb-live',
            name: 'USB LIVE INPUT',
            inputChannels: 2,
            nominalSampleRate: 48000,
            bufferFrames: 256,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MixerDeskView(audioEngine: engine),
        ),
      );

      engine.emitRoute(AudioRouteState.deviceLost);
      await tester.pump();

      expect(find.text('DEVICE LOST'), findsOneWidget);
      expect(find.text('REFRESH DEVICES'), findsOneWidget);

      await tester.tap(find.text('REFRESH DEVICES'));
      await tester.pumpAndSettle();

      expect(engine.refreshCalls, 1);
      expect(find.text('AUDIO PATCHBAY MATRIX & INPUT ROUTING'), findsOneWidget);
      expect(find.text('USB LIVE INPUT'), findsOneWidget);
      expect(find.text('Rekordbox (App Stream Loopback)'), findsNothing);
      expect(tester.takeException(), isNull);

      await engine.dispose();
    },
  );
}

class _FakeAudioEngine implements AudioEngine {
  _FakeAudioEngine({required this.inputs});

  final List<AudioInputEndpoint> inputs;
  final StreamController<AudioRouteState> _routeStates =
      StreamController<AudioRouteState>.broadcast();
  int refreshCalls = 0;
  AudioRouteState _routeState = AudioRouteState.idle;

  @override
  EngineState get state => EngineState.idle;

  @override
  AudioRouteState get routeState => _routeState;

  @override
  Stream<AudioRouteState> get routeStates => _routeStates.stream;

  void emitRoute(AudioRouteState state) {
    _routeState = state;
    _routeStates.add(state);
  }

  @override
  Future<List<AudioInputEndpoint>> refreshInputDevices() async {
    refreshCalls += 1;
    return inputs;
  }

  @override
  Stream<List<ChannelMeterSnapshot>> get channelMeters => const Stream.empty();

  @override
  Stream<MasterMeterSnapshot> get masterMeters => const Stream.empty();

  @override
  Stream<TrackMatch> get trackMatches => const Stream.empty();

  @override
  Future<void> initialize({int sampleRate = 48000, int framesPerBuffer = 256}) async {}

  @override
  Future<void> addChannel(InputChannelConfig channel) async {}

  @override
  Future<void> removeChannel(String channelId) async {}

  @override
  Future<void> setTrim(String channelId, double db) async {}

  @override
  Future<void> setFader(String channelId, double value) async {}

  @override
  Future<void> setMute(String channelId, bool value) async {}

  @override
  Future<void> setSolo(String channelId, bool value) async {}

  @override
  Future<void> setMasterGain(double db) async {}

  @override
  Future<void> startRecording(String filePath) async {}

  @override
  Future<void> stopRecording() async {}

  @override
  Future<void> startBroadcast(BroadcastTarget target) async {}

  @override
  Future<void> stopBroadcast() async {}

  @override
  Future<void> dispose() async {
    await _routeStates.close();
  }
}
