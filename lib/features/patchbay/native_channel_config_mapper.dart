import 'dart:math' as math;

import '../../audio/audio_engine_bridge.dart';
import 'patchbay_routing_modal.dart';

InputChannelConfig mapPatchbayResultToNativeConfig({
  required PatchbayChannelResult result,
  required String channelId,
}) {
  final kind = switch (result.endpoint.type) {
    AudioSourceType.hardwareInput => AudioInputKind.hardware,
    AudioSourceType.applicationLoopback => AudioInputKind.applicationLoopback,
  };

  return InputChannelConfig(
    id: channelId,
    name: result.channelName,
    kind: kind,
    endpointId: result.endpoint.id,
    channelPairIndex: result.channelPairIndex,
    trimDb: result.initialTrimDb,
  );
}

double masterFaderToDb(double normalized) {
  final value = normalized.clamp(0.0, 1.0).toDouble();
  if (value <= 0) return -90.0;
  return 20.0 * math.log(value) / math.ln10;
}
