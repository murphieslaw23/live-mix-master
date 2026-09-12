import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../audio/web/browser_capture_controller.dart';
import '../audio/web/browser_capture_runtime.dart';
import '../audio/web/browser_mixer_controller.dart';
import '../audio/web/browser_recording_controller.dart';
import '../design/live_mix_tokens.dart';
import '../design/web_reference_tokens.dart';
import '../features/monitor/compact_monitor_view.dart';
import '../services/web/browser_fingerprint_lookup_controller.dart';
import 'app_surface_web.dart' show WebReleaseShell;
import 'web_live_mixer_reference.dart';
import 'web_reference_live_state.dart';

Widget buildPrimaryOperatorSurface() => const WebReferenceSurface();

/// Responsive Web composition backed by one shared W5 browser runtime.
///
/// Desktop and compact reference views are projections of verified browser
/// controller state. The operator drawer receives the same controller
/// instances, so opening it never creates a second MediaStream/AudioWorklet
/// graph merely to expose the lower-level W5 controls.
class WebReferenceSurface extends StatefulWidget {
  const WebReferenceSurface({super.key});

  @override
  State<WebReferenceSurface> createState() => _WebReferenceSurfaceState();
}

class _WebReferenceSurfaceState extends State<WebReferenceSurface> {
  late final BrowserWebRuntime _runtime;

  @override
  void initState() {
    super.initState();
    _runtime = createBrowserWebRuntime();
    _runtime.captureController.addListener(_handleCaptureState);
    _runtime.recordingController.addListener(_handleRecordingState);
    _runtime.fingerprintController.addListener(_handleFingerprintState);
    _runtime.mixerController.addListener(_handleMixerState);
    unawaited(_runtime.captureController.probe());
  }

  @override
  void dispose() {
    _runtime.captureController.removeListener(_handleCaptureState);
    _runtime.recordingController.removeListener(_handleRecordingState);
    _runtime.fingerprintController.removeListener(_handleFingerprintState);
    _runtime.mixerController.removeListener(_handleMixerState);
    // BrowserWebRuntime is application-scoped on Web; do not dispose its
    // controllers when this presentation widget is rebuilt.
    super.dispose();
  }

  void _handleCaptureState(BrowserCaptureState _) => _refresh();
  void _handleRecordingState(BrowserRecordingState _) => _refresh();
  void _handleFingerprintState(BrowserFingerprintLookupState _) => _refresh();
  void _handleMixerState(BrowserMixerState _) => _refresh();

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  WebReferenceLiveState get _liveState =>
      WebReferenceLiveState.fromBrowserStates(
        capture: _runtime.captureController.state,
        mixer: _runtime.mixerController.state,
        recording: _runtime.recordingController.state,
        fingerprint: _runtime.fingerprintController.state,
      );

  Future<void> _toggleRecording() async {
    if (_liveState.recordingActive) {
      await _runtime.recordingController.stopRecording();
    } else {
      await _runtime.recordingController.startRecording();
    }
  }

  @override
  Widget build(BuildContext context) {
    final liveState = _liveState;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < WebReferenceTokens.compactBreakpoint;
        final drawerWidth = math.min(
          WebReferenceTokens.operatorDrawerMaxWidth,
          math.max(320.0, constraints.maxWidth * .78),
        );

        return Scaffold(
          key: const ValueKey('web-reference-shell'),
          backgroundColor: LiveMixTokens.surfaceBase,
          endDrawerEnableOpenDragGesture: false,
          endDrawer: SizedBox(
            width: drawerWidth,
            child: Drawer(
              backgroundColor: LiveMixTokens.surfaceBase,
              child: WebReleaseShell(
                controller: _runtime.captureController,
                recordingController: _runtime.recordingController,
                fingerprintController: _runtime.fingerprintController,
                mixerController: _runtime.mixerController,
              ),
            ),
          ),
          body: Builder(
            builder: (scaffoldContext) {
              void openOperator() =>
                  Scaffold.of(scaffoldContext).openEndDrawer();

              return compact
                  ? _CompactReferenceBody(
                      liveState: liveState,
                      onOpenOperator: openOperator,
                    )
                  : _DesktopReferenceBody(
                      liveState: liveState,
                      onOpenOperator: openOperator,
                      onFaderChanged: (value) =>
                          unawaited(_runtime.mixerController.setFader(value)),
                      onMutedChanged: (value) =>
                          unawaited(_runtime.mixerController.setMuted(value)),
                      onSoloChanged: (value) =>
                          unawaited(_runtime.mixerController.setSolo(value)),
                      onToggleRecording: () => unawaited(_toggleRecording()),
                    );
            },
          ),
        );
      },
    );
  }
}

class _DesktopReferenceBody extends StatelessWidget {
  const _DesktopReferenceBody({
    required this.liveState,
    required this.onOpenOperator,
    required this.onFaderChanged,
    required this.onMutedChanged,
    required this.onSoloChanged,
    required this.onToggleRecording,
  });

  final WebReferenceLiveState liveState;
  final VoidCallback onOpenOperator;
  final ValueChanged<double> onFaderChanged;
  final ValueChanged<bool> onMutedChanged;
  final ValueChanged<bool> onSoloChanged;
  final VoidCallback onToggleRecording;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _DesktopRail(onOpenOperator: onOpenOperator),
        Expanded(
          child: WebLiveMixerReference(
            liveState: liveState,
            onFaderChanged: onFaderChanged,
            onMutedChanged: onMutedChanged,
            onSoloChanged: onSoloChanged,
            onToggleRecording: onToggleRecording,
            onOpenOperator: onOpenOperator,
          ),
        ),
      ],
    );
  }
}

class _DesktopRail extends StatelessWidget {
  const _DesktopRail({required this.onOpenOperator});

  final VoidCallback onOpenOperator;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: WebReferenceTokens.desktopRailWidth,
      decoration: const BoxDecoration(
        color: LiveMixTokens.surfaceBase,
        border: Border(
          right: BorderSide(
            color: LiveMixTokens.surfaceStrip,
            width: WebReferenceTokens.panelBorder,
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 82),
            const _RailItem(label: 'Mixer', active: true),
            const _RailItem(label: 'Patchbay'),
            const _RailItem(label: 'Session'),
            const _RailItem(label: 'Settings'),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(8),
              child: IconButton(
                tooltip: 'WEB OPERATOR',
                onPressed: onOpenOperator,
                constraints: const BoxConstraints(
                  minWidth: LiveMixTokens.minimumTarget,
                  minHeight: LiveMixTokens.minimumTarget,
                ),
                style: IconButton.styleFrom(
                  foregroundColor: LiveMixTokens.textPrimary,
                  backgroundColor: LiveMixTokens.surfaceRack,
                  side: const BorderSide(color: LiveMixTokens.accentCopper),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                icon: const Icon(Icons.tune_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({required this.label, this.active = false});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: active ? LiveMixTokens.surfaceStrip : LiveMixTokens.surfaceBase,
        border: Border(
          left: BorderSide(
            color: active ? LiveMixTokens.accentOchre : Colors.transparent,
            width: 4,
          ),
          bottom: const BorderSide(color: LiveMixTokens.surfaceStrip),
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: LiveMixTextStyles.uiLabel.copyWith(
          color: active
              ? LiveMixTokens.textPrimary
              : LiveMixTokens.textSecondary,
        ),
      ),
    );
  }
}

class _CompactReferenceBody extends StatelessWidget {
  const _CompactReferenceBody({
    required this.liveState,
    required this.onOpenOperator,
  });

  final WebReferenceLiveState liveState;
  final VoidCallback onOpenOperator;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: CompactMonitorView(
            isStreaming: liveState.isStreaming,
            broadcastConfigured: liveState.broadcastConfigured,
            isRecording: liveState.recordingActive,
            currentTrackTitle: liveState.currentTrackTitle,
            currentArtist: liveState.currentArtist,
            streamBitrateKbps: liveState.streamBitrateKbps,
            masterPeakLevel: liveState.masterPeakLevel,
            matchConfidence: liveState.matchConfidence,
            loudnessLufs: liveState.loudnessLufs,
            truePeakDbtp: liveState.truePeakDbtp,
            limiterActive:
                liveState.mixerEnabled ? liveState.limiterActive : null,
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: SafeArea(
            child: IconButton(
              tooltip: 'WEB OPERATOR',
              onPressed: onOpenOperator,
              constraints: const BoxConstraints(
                minWidth: LiveMixTokens.minimumTarget,
                minHeight: LiveMixTokens.minimumTarget,
              ),
              style: IconButton.styleFrom(
                foregroundColor: LiveMixTokens.textPrimary,
                backgroundColor:
                    LiveMixTokens.surfaceRack.withValues(alpha: .94),
                side: const BorderSide(color: LiveMixTokens.accentCopper),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              icon: const Icon(Icons.tune_rounded),
            ),
          ),
        ),
      ],
    );
  }
}
