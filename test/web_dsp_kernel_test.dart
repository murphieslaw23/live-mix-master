import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/web/web_dsp_kernel.dart';

class _ExpectedMeter {
  const _ExpectedMeter({
    required this.id,
    required this.processed,
    required this.peakLeft,
    required this.peakRight,
    required this.rmsLeft,
    required this.rmsRight,
    required this.clipping,
  });

  final String id;
  final bool processed;
  final double peakLeft;
  final double peakRight;
  final double rmsLeft;
  final double rmsRight;
  final bool clipping;
}

class _FixtureVector {
  const _FixtureVector({
    required this.name,
    required this.masterGain,
    required this.channels,
    required this.expectedOutput,
    required this.limiterActive,
    required this.masterPeakLeft,
    required this.masterPeakRight,
    required this.meters,
  });

  final String name;
  final double masterGain;
  final List<WebDspChannelBlock> channels;
  final List<double> expectedOutput;
  final bool limiterActive;
  final double masterPeakLeft;
  final double masterPeakRight;
  final List<_ExpectedMeter> meters;
}

List<double> _parseFloatList(String value) {
  if (value == '~') {
    return const <double>[];
  }
  return value.split(',').map(double.parse).toList(growable: false);
}

_ExpectedMeter _parseMeter(String value) {
  final parts = value.split(';');
  if (parts.length != 7) {
    throw FormatException('meter spec must contain 7 fields: $value');
  }
  return _ExpectedMeter(
    id: parts[0],
    processed: parts[1] == '1',
    peakLeft: double.parse(parts[2]),
    peakRight: double.parse(parts[3]),
    rmsLeft: double.parse(parts[4]),
    rmsRight: double.parse(parts[5]),
    clipping: parts[6] == '1',
  );
}

_FixtureVector _parseVector(String line) {
  final fields = line.split('\t');
  if (fields.length != 8) {
    throw FormatException('fixture row must contain 8 fields: $line');
  }

  final channels = fields[2] == '~'
      ? const <WebDspChannelBlock>[]
      : fields[2].split('|').map((spec) {
          final parts = spec.split(';');
          if (parts.length != 6) {
            throw FormatException('channel spec must contain 6 fields: $spec');
          }
          return WebDspChannelBlock(
            id: parts[0],
            linearTrim: double.parse(parts[1]),
            fader: double.parse(parts[2]),
            muted: parts[3] == '1',
            solo: parts[4] == '1',
            interleavedStereo: Float32List.fromList(_parseFloatList(parts[5])),
          );
        }).toList(growable: false);

  return _FixtureVector(
    name: fields[0],
    masterGain: double.parse(fields[1]),
    channels: channels,
    expectedOutput: _parseFloatList(fields[3]),
    limiterActive: fields[4] == '1',
    masterPeakLeft: double.parse(fields[5]),
    masterPeakRight: double.parse(fields[6]),
    meters: fields[7] == '~'
        ? const <_ExpectedMeter>[]
        : fields[7].split('|').map(_parseMeter).toList(growable: false),
  );
}

List<_FixtureVector> _loadVectors() {
  return File('test/fixtures/dsp_parity_vectors.tsv')
      .readAsLinesSync()
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .map(_parseVector)
      .toList(growable: false);
}

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

    test('matches every shared DSP parity vector', () {
      final vectors = _loadVectors();
      expect(vectors.length, greaterThanOrEqualTo(11));

      for (final vector in vectors) {
        final result = WebDspKernel.processStereoBlock(
          channels: vector.channels,
          masterGainLinear: vector.masterGain,
        );

        expect(result.output.length, vector.expectedOutput.length, reason: vector.name);
        for (var index = 0; index < vector.expectedOutput.length; index++) {
          expect(result.output[index], closeTo(vector.expectedOutput[index], 1e-6), reason: '${vector.name} output[$index]');
        }
        expect(result.limiterActive, vector.limiterActive, reason: vector.name);
        expect(result.masterPeakLeft, closeTo(vector.masterPeakLeft, 1e-6), reason: vector.name);
        expect(result.masterPeakRight, closeTo(vector.masterPeakRight, 1e-6), reason: vector.name);

        final metersById = {for (final meter in result.channelMeters) meter.channelId: meter};
        for (final expected in vector.meters) {
          if (!expected.processed) {
            expect(metersById.containsKey(expected.id), isFalse, reason: '${vector.name} ${expected.id} should be skipped');
            continue;
          }
          final actual = metersById[expected.id];
          expect(actual, isNotNull, reason: '${vector.name} missing ${expected.id} meter');
          expect(actual!.peakLeft, closeTo(expected.peakLeft, 1e-6), reason: '${vector.name} ${expected.id} peakLeft');
          expect(actual.peakRight, closeTo(expected.peakRight, 1e-6), reason: '${vector.name} ${expected.id} peakRight');
          expect(actual.rmsLeft, closeTo(expected.rmsLeft, 1e-6), reason: '${vector.name} ${expected.id} rmsLeft');
          expect(actual.rmsRight, closeTo(expected.rmsRight, 1e-6), reason: '${vector.name} ${expected.id} rmsRight');
          expect(actual.clipping, expected.clipping, reason: '${vector.name} ${expected.id} clipping');
        }
      }
    });
  });
}