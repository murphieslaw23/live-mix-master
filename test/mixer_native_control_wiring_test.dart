import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop mixer forwards native engine and control mutations', () {
    final wrapper = File('lib/features/mixer/mixer_desk_view.dart')
        .readAsStringSync();
    final mixer = File('lib/features/mixer/mixer_desk_view_impl.dart')
        .readAsStringSync();

    expect(wrapper, contains('audioEngine: widget.audioEngine'));
    expect(mixer, contains("ValueKey('channel-fader-\${channel.id}')"));
    expect(mixer, contains("ValueKey('channel-mute-\${channel.id}')"));
    expect(mixer, contains("ValueKey('channel-solo-\${channel.id}')"));
    expect(mixer, contains("ValueKey('master-fader')"));
    expect(mixer, contains('audioEngine?.setFader'));
    expect(mixer, contains('audioEngine?.setMute'));
    expect(mixer, contains('audioEngine?.setSolo'));
    expect(mixer, contains('audioEngine?.setTrim'));
    expect(mixer, contains('audioEngine?.setMasterGain'));
    expect(mixer, contains('mapPatchbayResultToNativeConfig'));
  });
}
