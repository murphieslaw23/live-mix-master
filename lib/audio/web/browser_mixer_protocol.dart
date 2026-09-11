class BrowserMixerConfiguration {
  const BrowserMixerConfiguration({
    required this.masterGainLinear,
    required this.telemetryEvery,
    required this.channels,
  });

  final double masterGainLinear;
  final int telemetryEvery;
  final List<BrowserMixerChannelConfiguration> channels;

  Map<String, Object?> toMessage() => <String, Object?>{
        'type': 'configure',
        'masterGainLinear': masterGainLinear,
        'telemetryEvery': telemetryEvery,
        'channels': channels
            .map((channel) => channel.toMessage())
            .toList(growable: false),
      };
}

class BrowserMixerChannelConfiguration {
  const BrowserMixerChannelConfiguration({
    required this.id,
    required this.linearTrim,
    required this.fader,
    required this.muted,
    required this.solo,
  });

  final String id;
  final double linearTrim;
  final double fader;
  final bool muted;
  final bool solo;

  Map<String, Object?> toMessage() => <String, Object?>{
        'id': id,
        'linearTrim': linearTrim,
        'fader': fader,
        'muted': muted,
        'solo': solo,
      };
}

class BrowserMixerTelemetry {
  const BrowserMixerTelemetry({
    required this.channelMeters,
    required this.masterPeakLeft,
    required this.masterPeakRight,
    required this.limiterActive,
  });

  final Map<String, BrowserChannelMeter> channelMeters;
  final double masterPeakLeft;
  final double masterPeakRight;
  final bool limiterActive;

  static BrowserMixerTelemetry? tryParse(Object? value) {
    final root = _stringKeyedMap(value);
    if (root == null || root['type'] != 'telemetry') {
      return null;
    }

    final rawMeters = root['channelMeters'];
    if (rawMeters is! List) {
      return null;
    }

    final masterPeakLeft = _finiteDouble(root['masterPeakLeft']);
    final masterPeakRight = _finiteDouble(root['masterPeakRight']);
    final limiterActive = root['limiterActive'];
    if (masterPeakLeft == null ||
        masterPeakRight == null ||
        limiterActive is! bool) {
      return null;
    }

    final meters = <String, BrowserChannelMeter>{};
    for (final rawMeter in rawMeters) {
      final meterMap = _stringKeyedMap(rawMeter);
      if (meterMap == null) {
        return null;
      }
      final channelId = meterMap['channelId'];
      final peakLeft = _finiteDouble(meterMap['peakLeft']);
      final peakRight = _finiteDouble(meterMap['peakRight']);
      final rmsLeft = _finiteDouble(meterMap['rmsLeft']);
      final rmsRight = _finiteDouble(meterMap['rmsRight']);
      final clipping = meterMap['clipping'];
      if (channelId is! String ||
          channelId.trim().isEmpty ||
          peakLeft == null ||
          peakRight == null ||
          rmsLeft == null ||
          rmsRight == null ||
          clipping is! bool ||
          meters.containsKey(channelId)) {
        return null;
      }
      meters[channelId] = BrowserChannelMeter(
        peakLeft: peakLeft,
        peakRight: peakRight,
        rmsLeft: rmsLeft,
        rmsRight: rmsRight,
        clipping: clipping,
      );
    }

    return BrowserMixerTelemetry(
      channelMeters: Map<String, BrowserChannelMeter>.unmodifiable(meters),
      masterPeakLeft: masterPeakLeft,
      masterPeakRight: masterPeakRight,
      limiterActive: limiterActive,
    );
  }
}

class BrowserChannelMeter {
  const BrowserChannelMeter({
    required this.peakLeft,
    required this.peakRight,
    required this.rmsLeft,
    required this.rmsRight,
    required this.clipping,
  });

  final double peakLeft;
  final double peakRight;
  final double rmsLeft;
  final double rmsRight;
  final bool clipping;
}

Map<String, Object?>? _stringKeyedMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      return null;
    }
    result[key] = entry.value;
  }
  return result;
}

double? _finiteDouble(Object? value) {
  if (value is! num) {
    return null;
  }
  final result = value.toDouble();
  return result.isFinite ? result : null;
}
