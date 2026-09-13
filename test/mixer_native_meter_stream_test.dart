import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native mixer consumes engine meters instead of synthetic levels', () {
    final mixer = File('lib/features/mixer/mixer_desk_view_impl.dart')
        .readAsStringSync();

    expect(mixer, contains('audioEngine?.channelMeters.listen'));
    expect(mixer, contains('audioEngine?.masterMeters.listen'));
    expect(mixer, contains('_nativeChannelMeters'));
    expect(mixer, contains('_nativeMasterMeter'));
    expect(mixer, contains('SAMPLE PEAK'));
    expect(mixer, contains('POST LIMITER'));
    expect(mixer, contains('audioEngine == null'));
    expect(mixer, isNot(contains("'-14.2 LUFS'")));
    expect(mixer, isNot(contains("'-6.0 dBTP'")));
  });
}
