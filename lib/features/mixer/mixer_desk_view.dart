import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../audio/audio_engine_bridge.dart';
import '../../services/mixer_service_ports.dart';
import '../patchbay/audio_route_recovery_banner.dart';
import 'mixer_desk_view_impl.dart' as impl;
import 'native_mixer_desk_view.dart';

export 'mixer_desk_view_impl.dart' show ChannelData;

/// Stable public mixer surface.
///
/// Reference/Web mode keeps the approved fixture-driven implementation.
/// Desktop native mode selects a separate surface whose controls and meters are
/// wired only to the injected [AudioEngine].
class MixerDeskView extends StatefulWidget {
  const MixerDeskView({
    super.key,
    this.audioEngine,
    this.fingerprintService,
    this.recordingWriter,
    this.onOpenAudioSettings,
  });

  final AudioEngine? audioEngine;
  final MixerFingerprintPort? fingerprintService;
  final MixerRecordingPort? recordingWriter;
  final Future<void> Function()? onOpenAudioSettings;

  @override
  State<MixerDeskView> createState() => _MixerDeskViewState();
}

class _MixerDeskViewState extends State<MixerDeskView> {
  StreamSubscription<AudioRouteState>? _routeSubscription;
  late AudioRouteState _routeState;

  @override
  void initState() {
    super.initState();
    _bindAudioEngine();
  }

  @override
  void didUpdateWidget(covariant MixerDeskView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioEngine != widget.audioEngine) {
      unawaited(_routeSubscription?.cancel());
      _bindAudioEngine();
    }
  }

  void _bindAudioEngine() {
    final engine = widget.audioEngine;
    _routeState = engine?.routeState ?? AudioRouteState.idle;
    _routeSubscription = engine?.routeStates.listen((state) {
      if (!mounted) return;
      setState(() => _routeState = state);
    });
  }

  Future<void> _handleRecovery() async {
    if (_routeState == AudioRouteState.permissionDenied) {
      await widget.onOpenAudioSettings?.call();
      return;
    }
    await widget.audioEngine?.refreshInputDevices();
  }

  Future<void> _refreshPermission() async {
    await widget.audioEngine?.refreshInputDevices();
  }

  @override
  void dispose() {
    unawaited(_routeSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = widget.audioEngine;
    final mixer = engine == null
        ? impl.MixerDeskView(
            fingerprintService: widget.fingerprintService,
            recordingWriter: widget.recordingWriter,
          )
        : NativeMixerDeskView(
            audioEngine: engine,
            fingerprintService: widget.fingerprintService,
            recordingWriter: widget.recordingWriter,
          );

    if (engine == null ||
        (_routeState == AudioRouteState.idle ||
            _routeState == AudioRouteState.active)) {
      return mixer;
    }

    return Column(
      children: [
        AudioRouteRecoveryBanner(
          state: _routeState,
          onRecoveryRequested: () => unawaited(_handleRecovery()),
          onRefreshRequested: _routeState == AudioRouteState.permissionDenied
              ? () => unawaited(_refreshPermission())
              : null,
        ),
        Expanded(child: mixer),
      ],
    );
  }
}
