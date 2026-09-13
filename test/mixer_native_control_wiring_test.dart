import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop mixer selects native surface and wires control mutations', () {
    final wrapper = File('lib/features/mixer/mixer_desk_view.dart')
        .readAsStringSync();
    final mixer = File('lib/features/mixer/native_mixer_desk_view.dart')
        .readAsStringSync();

    expect(wrapper, contains('NativeMixerDeskView('));
    expect(wrapper, contains('audioEngine: engine'));
    expect(mixer, contains("ValueKey('channel-fader-\${channel.id}')"));
    expect(mixer, contains("ValueKey('channel-mute-\${channel.id}')"));
    expect(mixer, contains("ValueKey('channel-solo-\${channel.id}')"));
    expect(mixer, contains("ValueKey('channel-trim-\${channel.id}')"));
    expect(mixer, contains("ValueKey('master-fader')"));
    expect(mixer, contains('widget.audioEngine.setFader'));
    expect(mixer, contains('widget.audioEngine.setMute'));
    expect(mixer, contains('widget.audioEngine.setSolo'));
    expect(mixer, contains('widget.audioEngine.setTrim'));
    expect(mixer, contains('widget.audioEngine.setMasterGain'));
    expect(mixer, contains('mapPatchbayResultToNativeConfig'));
    expect(mixer, contains('refreshInputDevices'));
  });
}
