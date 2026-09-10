import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/web/web_dsp_kernel.dart';

void main() {
  group('WebDspKernel native-parity contract', () {
    test('applies linear trim times squared fader and reports stereo peak/RMS', () {
      final result = WebDspKernel.processStereoBlock(
        channels: [
          WebDspChannelBlock(
            id: 'deck-a',
            interleavedStereo: Float32List.fromList([1, -1, 0.5, -0.5]),
            linearTrim: 1,
            fader: 0.5,
          ),
        ],
      );

      expect(result.output[0], closeTo(0.25, 1e-9));
      expect(result.output[1], closeTo(-0.25, 1e-9));
      expect(result.output[2], closeTo(0.125, 1e-9));
      expect(result.output[3], closeTo(-0.125, 1e-9));

      final meter = result.channelMeters.single;
      expect(meter.channelId, 'deck-a');
      expect(meter.peakLeft, closeTo(0.25, 1e-9));
      expect(meter.peakRight, closeTo(0.25, 1e-9));
      expect(
        meter.rmsLeft,
        closeTo(math.sqrt((0.25 * 0.25 + 0.125 * 0.125) / 2), 1e-9),
      );
      expect(meter.rmsRight, closeTo(meter.rmsLeft, 1e-9));
      expect(meter.clipping, isFalse);
    });

    test('solo excludes non-solo channels and mute excludes muted channels', () {
      final result = WebDspKernel.processStereoBlock(
        channels: [
          WebDspChannelBlock(
            id: 'solo',
            interleavedStereo: Float32List.fromList([0.25, 0.25]),
            linearTrim: 1,
            fader: 1,
            solo: true,
          ),
          WebDspChannelBlock(
            id: 'not-solo',
            interleavedStereo: Float32List.fromList([0.5, 0.5]),
            linearTrim: 1,
            fader: 1,
          ),
          WebDspChannelBlock(
            id: 'muted-solo',
            interleavedStereo: Float32List.fromList([0.75, 0.75]),
            linearTrim: 1,
            fader: 1,
            solo: true,
            muted: true,
          ),
        ],
      );

      expect(result.output[0], closeTo(0.25, 1e-9));
      expect(result.output[1], closeTo(0.25, 1e-9));
      expect(result.channelMeters.map((meter) => meter.channelId), ['solo']);
    });

    test('master sample ceiling clamps to 0.98 and reports limiter activity', () {
      final result = WebDspKernel.processStereoBlock(
        channels: [
          WebDspChannelBlock(
            id: 'hot',
            interleavedStereo: Float32List.fromList([2, -2]),
            linearTrim: 1,
            fader: 1,
          ),
        ],
        masterGainLinear: 1,
      );

      expect(result.output[0], closeTo(0.98, 1e-9));
      expect(result.output[1], closeTo(-0.98, 1e-9));
      expect(result.masterPeakLeft, closeTo(0.98, 1e-9));
      expect(result.masterPeakRight, closeTo(0.98, 1e-9));
      expect(result.limiterActive, isTrue);
      expect(result.channelMeters.single.clipping, isTrue);
    });
  });
}
