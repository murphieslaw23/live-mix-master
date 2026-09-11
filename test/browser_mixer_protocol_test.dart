import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/web/browser_mixer_protocol.dart';

void main() {
  group('Browser mixer protocol', () {
    test('configuration serializes the existing Worklet configure schema', () {
      const configuration = BrowserMixerConfiguration(
        masterGainLinear: 1,
        telemetryEvery: 20,
        channels: <BrowserMixerChannelConfiguration>[
          BrowserMixerChannelConfiguration(
            id: 'mic-1',
            linearTrim: 1,
            fader: .5,
            muted: true,
            solo: false,
          ),
        ],
      );

      expect(configuration.toMessage(), <String, Object?>{
        'type': 'configure',
        'masterGainLinear': 1.0,
        'telemetryEvery': 20,
        'channels': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'mic-1',
            'linearTrim': 1.0,
            'fader': .5,
            'muted': true,
            'solo': false,
          },
        ],
      });
    });

    test('telemetry preserves stereo peak RMS and clipping fields', () {
      final telemetry = BrowserMixerTelemetry.tryParse(<String, Object?>{
        'type': 'telemetry',
        'channelMeters': <Map<String, Object?>>[
          <String, Object?>{
            'channelId': 'mic-1',
            'peakLeft': .4,
            'peakRight': .5,
            'rmsLeft': .2,
            'rmsRight': .25,
            'clipping': false,
          },
        ],
        'masterPeakLeft': .4,
        'masterPeakRight': .5,
        'limiterActive': false,
      });

      expect(telemetry, isNotNull);
      expect(telemetry!.channelMeters.keys, <String>['mic-1']);
      expect(telemetry.channelMeters['mic-1']!.peakLeft, .4);
      expect(telemetry.channelMeters['mic-1']!.peakRight, .5);
      expect(telemetry.channelMeters['mic-1']!.rmsLeft, .2);
      expect(telemetry.channelMeters['mic-1']!.rmsRight, .25);
      expect(telemetry.channelMeters['mic-1']!.clipping, isFalse);
      expect(telemetry.masterPeakLeft, .4);
      expect(telemetry.masterPeakRight, .5);
      expect(telemetry.limiterActive, isFalse);
    });

    test('malformed or non-finite telemetry is rejected without throwing', () {
      expect(
        BrowserMixerTelemetry.tryParse(<String, Object?>{
          'type': 'telemetry',
          'channelMeters': <Object?>[],
          'masterPeakLeft': double.nan,
          'masterPeakRight': .5,
          'limiterActive': false,
        }),
        isNull,
      );
      expect(
        BrowserMixerTelemetry.tryParse(<String, Object?>{
          'type': 'telemetry',
          'channelMeters': <Map<String, Object?>>[
            <String, Object?>{
              'channelId': '',
              'peakLeft': .4,
              'peakRight': .5,
              'rmsLeft': .2,
              'rmsRight': .25,
              'clipping': false,
            },
          ],
          'masterPeakLeft': .4,
          'masterPeakRight': .5,
          'limiterActive': false,
        }),
        isNull,
      );
      expect(BrowserMixerTelemetry.tryParse(<String, Object?>{'type': 'pcm'}), isNull);
    });
  });
}
