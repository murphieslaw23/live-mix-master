import 'package:flutter/widgets.dart';

import '../../audio/audio_engine_bridge.dart';
import '../../services/fingerprint_service.dart';
import '../../services/lossless_recording_writer.dart';
import 'mixer_desk_view_impl.dart' as impl;

export 'mixer_desk_view_impl.dart' show ChannelData;

/// Stable public mixer surface.
///
/// The visual implementation remains isolated from platform bootstrap code.
/// Desktop may inject a native [AudioEngine]; Web leaves it null and continues
/// using the browser-owned operator surface.
class MixerDeskView extends StatelessWidget {
  const MixerDeskView({
    super.key,
    this.audioEngine,
    this.fingerprintService,
    this.recordingWriter,
  });

  final AudioEngine? audioEngine;
  final FingerprintService? fingerprintService;
  final LosslessRecordingWriter? recordingWriter;

  @override
  Widget build(BuildContext context) {
    return impl.MixerDeskView(
      fingerprintService: fingerprintService,
      recordingWriter: recordingWriter,
    );
  }
}
