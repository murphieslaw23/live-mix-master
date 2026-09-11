import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/web/browser_mixer_controller.dart';
import 'package:live_mix_master/audio/web/browser_mixer_protocol.dart';

void main() {
  group('BrowserMixerController', () {
    test('attach sends neutral configuration and enables controls', () async {
      final gateway = _FakeMixerGateway();
      final controller = BrowserMixerController(gateway: gateway);

      await controller.attach('mic-1');

      expect(controller.state.enabled, isTrue);
      expect(controller.state.activeChannelId, 'mic-1');
      expect(controller.state.fader, 1.0);
      expect(controller.state.muted, isFalse);
      expect(controller.state.solo, isFalse);
      expect(gateway.configurations, hasLength(1));
      expect(gateway.configurations.single.masterGainLinear, 1.0);
      expect(gateway.configurations.single.telemetryEvery, 20);
      expect(gateway.configurations.single.channels.single.id, 'mic-1');
      expect(gateway.configurations.single.channels.single.linearTrim, 1.0);
      expect(gateway.configurations.single.channels.single.fader, 1.0);

      await controller.dispose();
      await gateway.dispose();
    });

    test('fader mute solo changes are serialized and reflected in state', () async {
      final gateway = _FakeMixerGateway();
      final controller = BrowserMixerController(gateway: gateway);
      await controller.attach('mic-1');

      await controller.setFader(.6);
      await controller.setMuted(true);
      await controller.setSolo(true);

      expect(controller.state.fader, .6);
      expect(controller.state.muted, isTrue);
      expect(controller.state.solo, isTrue);
      expect(gateway.configurations, hasLength(4));
      expect(gateway.configurations[1].channels.single.fader, .6);
      expect(gateway.configurations[2].channels.single.muted, isTrue);
      expect(gateway.configurations[3].channels.single.solo, isTrue);

      await controller.dispose();
      await gateway.dispose();
    });

    test('rapid fader writes coalesce to the latest pending configuration', () async {
      final gateway = _FakeMixerGateway();
      final controller = BrowserMixerController(gateway: gateway);
      await controller.attach('mic-1');

      final blocker = gateway.blockNextConfiguration();
      final first = controller.setFader(.2);
      await Future<void>.delayed(Duration.zero);
      final middle = controller.setFader(.4);
      final latest = controller.setFader(.6);

      expect(gateway.configurations, hasLength(2));
      expect(gateway.configurations.last.channels.single.fader, .2);

      blocker.complete();
      await Future.wait<void>(<Future<void>>[first, middle, latest]);

      expect(gateway.configurations, hasLength(3));
      expect(gateway.configurations.last.channels.single.fader, .6);

      await controller.dispose();
      await gateway.dispose();
    });

    test('fader is clamped to normalized range', () async {
      final gateway = _FakeMixerGateway();
      final controller = BrowserMixerController(gateway: gateway);
      await controller.attach('mic-1');

      await controller.setFader(2);
      expect(controller.state.fader, 1.0);
      await controller.setFader(-1);
      expect(controller.state.fader, 0.0);

      await controller.dispose();
      await gateway.dispose();
    });

    test('telemetry updates active channel and master meters', () async {
      final gateway = _FakeMixerGateway();
      final controller = BrowserMixerController(gateway: gateway);
      await controller.attach('mic-1');

      gateway.emit(
        const BrowserMixerTelemetry(
          channelMeters: <String, BrowserChannelMeter>{
            'mic-1': BrowserChannelMeter(
              peakLeft: .4,
              peakRight: .5,
              rmsLeft: .2,
              rmsRight: .25,
              clipping: false,
            ),
          },
          masterPeakLeft: .45,
          masterPeakRight: .55,
          limiterActive: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.channelMeter?.peakRight, .5);
      expect(controller.state.masterPeakLeft, .45);
      expect(controller.state.masterPeakRight, .55);
      expect(controller.state.limiterActive, isTrue);

      await controller.dispose();
      await gateway.dispose();
    });

    test('muted telemetry retains the last channel meter but refreshes master state', () async {
      final gateway = _FakeMixerGateway();
      final controller = BrowserMixerController(gateway: gateway);
      await controller.attach('mic-1');

      gateway.emit(
        const BrowserMixerTelemetry(
          channelMeters: <String, BrowserChannelMeter>{
            'mic-1': BrowserChannelMeter(
              peakLeft: .4,
              peakRight: .5,
              rmsLeft: .2,
              rmsRight: .25,
              clipping: false,
            ),
          },
          masterPeakLeft: .45,
          masterPeakRight: .55,
          limiterActive: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      gateway.emit(
        const BrowserMixerTelemetry(
          channelMeters: <String, BrowserChannelMeter>{},
          masterPeakLeft: 0,
          masterPeakRight: 0,
          limiterActive: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.channelMeter?.peakRight, .5);
      expect(controller.state.masterPeakLeft, 0);
      expect(controller.state.masterPeakRight, 0);
      expect(controller.state.limiterActive, isFalse);

      await controller.dispose();
      await gateway.dispose();
    });

    test('other-channel telemetry cannot replace the active channel meter', () async {
      final gateway = _FakeMixerGateway();
      final controller = BrowserMixerController(gateway: gateway);
      await controller.attach('mic-1');

      gateway.emit(
        const BrowserMixerTelemetry(
          channelMeters: <String, BrowserChannelMeter>{
            'other': BrowserChannelMeter(
              peakLeft: .8,
              peakRight: .8,
              rmsLeft: .4,
              rmsRight: .4,
              clipping: false,
            ),
          },
          masterPeakLeft: .8,
          masterPeakRight: .8,
          limiterActive: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.channelMeter, isNull);
      expect(controller.state.masterPeakLeft, .8);
      expect(controller.state.masterPeakRight, .8);

      await controller.dispose();
      await gateway.dispose();
    });

    test('detach disables controls and clears meters', () async {
      final gateway = _FakeMixerGateway();
      final controller = BrowserMixerController(gateway: gateway);
      await controller.attach('mic-1');
      gateway.emit(
        const BrowserMixerTelemetry(
          channelMeters: <String, BrowserChannelMeter>{
            'mic-1': BrowserChannelMeter(
              peakLeft: .4,
              peakRight: .5,
              rmsLeft: .2,
              rmsRight: .25,
              clipping: false,
            ),
          },
          masterPeakLeft: .45,
          masterPeakRight: .55,
          limiterActive: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      await controller.detach();

      expect(controller.state.enabled, isFalse);
      expect(controller.state.activeChannelId, isNull);
      expect(controller.state.channelMeter, isNull);
      expect(controller.state.masterPeakLeft, 0);
      expect(controller.state.masterPeakRight, 0);

      await controller.dispose();
      await gateway.dispose();
    });
  });
}

class _FakeMixerGateway implements BrowserMixerGateway {
  final StreamController<BrowserMixerTelemetry> _telemetry =
      StreamController<BrowserMixerTelemetry>.broadcast();
  final List<BrowserMixerConfiguration> configurations =
      <BrowserMixerConfiguration>[];
  Completer<void>? _nextConfigurationBlocker;

  @override
  Stream<BrowserMixerTelemetry> get telemetry => _telemetry.stream;

  @override
  Future<void> configure(BrowserMixerConfiguration configuration) async {
    configurations.add(configuration);
    final blocker = _nextConfigurationBlocker;
    _nextConfigurationBlocker = null;
    if (blocker != null) {
      await blocker.future;
    }
  }

  Completer<void> blockNextConfiguration() {
    final blocker = Completer<void>();
    _nextConfigurationBlocker = blocker;
    return blocker;
  }

  void emit(BrowserMixerTelemetry telemetry) {
    _telemetry.add(telemetry);
  }

  Future<void> dispose() => _telemetry.close();
}
