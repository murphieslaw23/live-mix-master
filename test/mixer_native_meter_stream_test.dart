import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/audio_engine_bridge.dart';
import 'package:live_mix_master/features/mixer/mixer_desk_view.dart';

void main() {
  testWidgets('native channel meter stream drives the attached channel meter',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);

    final engine = _MeterEngine();
    await tester.pumpWidget(MaterialApp(home: MixerDeskView(audioEngine: engine)));

    await tester.tap(find.text('ADD INPUT'));
    await tester.pumpAndSettle();
    expect(find.text('REAL INPUT'), findsOneWidget);

    await tester.tap(find.text('ATTACH CHANNEL STRIP'));
    await tester.pumpAndSettle();
    expect(engine.boundChannelId, isNotNull);

    engine.emitChannelMeter(
      ChannelMeterSnapshot(
        channelId: engine.boundChannelId!,
        meter: const StereoMeter(
          peakLeft: .25,
          peakRight: .10,
          rmsLeft: .12,
          rmsRight: .05,
          clipping: false,
        ),
      ),
    );
    await tester.pump();

    final meters = find.bySemanticsLabel('channel level meter');
    expect(meters, findsWidgets);
    expect(tester.getSemantics(meters.last).value, '25 percent');

    await engine.dispose();
  });
}

class _MeterEngine implements AudioEngine {
  final _route = StreamController<AudioRouteState>.broadcast();
  final _channels = StreamController<List<ChannelMeterSnapshot>>.broadcast();
  final _master = StreamController<MasterMeterSnapshot>.broadcast();
  String? boundChannelId;

  @override
  EngineState get state => EngineState.running;
  @override
  AudioRouteState get routeState => AudioRouteState.active;
  @override
  Stream<AudioRouteState> get routeStates => _route.stream;
  @override
  Stream<List<ChannelMeterSnapshot>> get channelMeters => _channels.stream;
  @override
  Stream<MasterMeterSnapshot> get masterMeters => _master.stream;
  @override
  Stream<TrackMatch> get trackMatches => const Stream.empty();

  void emitChannelMeter(ChannelMeterSnapshot value) => _channels.add([value]);

  @override
  Future<void> initialize({int sampleRate = 48000, int framesPerBuffer = 256}) async {}
  @override
  Future<List<AudioInputEndpoint>> refreshInputDevices() async => const [
        AudioInputEndpoint(
          uid: 'coreaudio:real-input',
          name: 'REAL INPUT',
          inputChannels: 2,
          nominalSampleRate: 48000,
          bufferFrames: 256,
        ),
      ];
  @override
  Future<void> addChannel(InputChannelConfig channel) async {
    boundChannelId = channel.id;
  }
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
    await _route.close();
    await _channels.close();
    await _master.close();
  }
}
