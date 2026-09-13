import 'package:flutter/widgets.dart';

import '../../audio/audio_engine_bridge.dart';
import '../../services/mixer_service_ports.dart';
import 'mixer_desk_view_impl.dart' as impl;

export 'mixer_desk_view_impl.dart' show ChannelData;

/// Stable public mixer surface.
///
/// The visual implementation remains isolated from platform bootstrap code.
/// Desktop may inject native audio and stable service ports; Web leaves them
/// null and continues using the browser-owned operator surface.
class MixerDeskView extends StatelessWidget {
  const MixerDeskView({
    super.key,
    this.audioEngine,
    this.fingerprintService,
    this.recordingWriter,
  });

  final AudioEngine? audioEngine;
  final MixerFingerprintPort? fingerprintService;
  final MixerRecordingPort? recordingWriter;

  @override
  Widget build(BuildContext context) {
    return impl.MixerDeskView(
      fingerprintService: fingerprintService,
      recordingWriter: recordingWriter,
    );
  }
}
