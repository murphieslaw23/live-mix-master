import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native mixer consumes engine meters instead of synthetic levels', () {
    final wrapper = File('lib/features/mixer/mixer_desk_view.dart')
        .readAsStringSync();
    final mixer = File('lib/features/mixer/native_mixer_desk_view.dart')
        .readAsStringSync();

    expect(wrapper, contains('engine == null'));
    expect(wrapper, contains('NativeMixerDeskView('));
    expect(mixer, contains('widget.audioEngine.channelMeters.listen'));
    expect(mixer, contains('widget.audioEngine.masterMeters.listen'));
    expect(mixer, contains('_nativeChannelMeters'));
    expect(mixer, contains('_nativeMasterMeter'));
    expect(mixer, contains('SAMPLE PEAK'));
    expect(mixer, contains('POST LIMITER'));
    expect(mixer, isNot(contains('LUFS')));
    expect(mixer, isNot(contains('dBTP')));
  });
}
