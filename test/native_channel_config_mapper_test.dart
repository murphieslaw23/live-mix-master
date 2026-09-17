import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/audio_engine_bridge.dart';
import 'package:live_mix_master/features/patchbay/native_channel_config_mapper.dart';
import 'package:live_mix_master/features/patchbay/patchbay_routing_modal.dart';

void main() {
  test('patchbay mapping preserves endpoint pair kind and trim', () {
    const result = PatchbayChannelResult(
      channelName: 'DECK B',
      endpoint: AudioEndpoint(
        id: 'device-uid',
        name: 'Four Channel Device',
        type: AudioSourceType.hardwareInput,
        channelCount: 4,
        deviceDriver: 'CoreAudio',
      ),
      channelPairIndex: 1,
      initialTrimDb: -3,
      channelColor: Colors.white,
    );

    final config = mapPatchbayResultToNativeConfig(
      result: result,
      channelId: 'deck-b',
    );

    expect(config.id, 'deck-b');
    expect(config.name, 'DECK B');
    expect(config.kind, AudioInputKind.hardware);
    expect(config.endpointId, 'device-uid');
    expect(config.channelPairIndex, 1);
    expect(config.trimDb, -3);
  });

  test('master fader conversion reaches silence and unity deterministically', () {
    expect(masterFaderToDb(0), -90);
    expect(masterFaderToDb(1), closeTo(0, 1e-12));
    expect(masterFaderToDb(.5), closeTo(-6.020599913, 1e-6));
  });
}
