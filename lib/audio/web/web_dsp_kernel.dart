import 'dart:math' as math;
import 'dart:typed_data';

const double webDspLimiterCeiling = 0.98;

class WebDspChannelBlock {
  const WebDspChannelBlock({
    required this.id,
    required this.interleavedStereo,
    this.linearTrim = 1,
    this.fader = 0.8,
    this.muted = false,
    this.solo = false,
  });

  final String id;
  final Float32List interleavedStereo;
  final double linearTrim;
  final double fader;
  final bool muted;
  final bool solo;
}

class WebDspChannelMeter {
  const WebDspChannelMeter({
    required this.channelId,
    required this.peakLeft,
    required this.peakRight,
    required this.rmsLeft,
    required this.rmsRight,
    required this.clipping,
  });

  final String channelId;
  final double peakLeft;
  final double peakRight;
  final double rmsLeft;
  final double rmsRight;
  final bool clipping;
}

class WebDspBlockResult {
  const WebDspBlockResult({
    required this.output,
    required this.channelMeters,
    required this.masterPeakLeft,
    required this.masterPeakRight,
    required this.limiterActive,
  });

  final List<double> output;
  final List<WebDspChannelMeter> channelMeters;
  final double masterPeakLeft;
  final double masterPeakRight;
  final bool limiterActive;
}

class WebDspKernel {
  const WebDspKernel._();

  static WebDspBlockResult processStereoBlock({
    required List<WebDspChannelBlock> channels,
    double masterGainLinear = 1,
  }) {
    final frameCount = _frameCount(channels);
    final output = List<double>.filled(frameCount * 2, 0);
    final meters = <WebDspChannelMeter>[];
    final anySolo = channels.any((channel) => channel.solo);

    for (final channel in channels) {
      if (channel.muted || (anySolo && !channel.solo)) {
        continue;
      }

      final gain = channel.linearTrim * channel.fader * channel.fader;
      var squareLeft = 0.0;
      var squareRight = 0.0;
      var peakLeft = 0.0;
      var peakRight = 0.0;

      for (var frame = 0; frame < frameCount; frame++) {
        final left = channel.interleavedStereo[frame * 2] * gain;
        final right = channel.interleavedStereo[frame * 2 + 1] * gain;

        output[frame * 2] += left;
        output[frame * 2 + 1] += right;

        peakLeft = math.max(peakLeft, left.abs());
        peakRight = math.max(peakRight, right.abs());
        squareLeft += left * left;
        squareRight += right * right;
      }

      meters.add(
        WebDspChannelMeter(
          channelId: channel.id,
          peakLeft: peakLeft,
          peakRight: peakRight,
          rmsLeft: frameCount == 0 ? 0 : math.sqrt(squareLeft / frameCount),
          rmsRight: frameCount == 0 ? 0 : math.sqrt(squareRight / frameCount),
          clipping: peakLeft >= 1 || peakRight >= 1,
        ),
      );
    }

    var masterPeakLeft = 0.0;
    var masterPeakRight = 0.0;
    var limiterActive = false;

    for (var frame = 0; frame < frameCount; frame++) {
      var left = output[frame * 2] * masterGainLinear;
      var right = output[frame * 2 + 1] * masterGainLinear;

      if (left.abs() > webDspLimiterCeiling ||
          right.abs() > webDspLimiterCeiling) {
        limiterActive = true;
        left = left.clamp(-webDspLimiterCeiling, webDspLimiterCeiling);
        right = right.clamp(-webDspLimiterCeiling, webDspLimiterCeiling);
      }

      output[frame * 2] = left;
      output[frame * 2 + 1] = right;
      masterPeakLeft = math.max(masterPeakLeft, left.abs());
      masterPeakRight = math.max(masterPeakRight, right.abs());
    }

    return WebDspBlockResult(
      output: output,
      channelMeters: List.unmodifiable(meters),
      masterPeakLeft: masterPeakLeft,
      masterPeakRight: masterPeakRight,
      limiterActive: limiterActive,
    );
  }

  static int _frameCount(List<WebDspChannelBlock> channels) {
    if (channels.isEmpty) {
      return 0;
    }

    final sampleCount = channels.first.interleavedStereo.length;
    if (sampleCount.isOdd) {
      throw ArgumentError.value(
        sampleCount,
        'interleavedStereo.length',
        'Stereo PCM must contain an even number of samples.',
      );
    }

    for (final channel in channels.skip(1)) {
      if (channel.interleavedStereo.length != sampleCount) {
        throw ArgumentError(
          'All channel blocks must contain the same number of stereo frames.',
        );
      }
    }

    return sampleCount ~/ 2;
  }
}
