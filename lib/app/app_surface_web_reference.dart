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

enum _WebReferenceSection {
  mixer,
  patchbay,
  session,
  settings,
  operator,
}

/// Responsive Web composition backed by one shared W5 browser runtime.
///
/// Desktop and compact reference views are projections of verified browser
/// controller state. Desktop navigation keeps one lower-level WebReleaseShell
/// alive behind the reference mixer so session/fingerprint state remains
/// continuous while the rail switches views. Compact layouts keep the same
/// functional shell in the operator drawer.
class WebReferenceSurface extends StatefulWidget {
  const WebReferenceSurface({super.key});

  @override
  State<WebReferenceSurface> createState() => _WebReferenceSurfaceState();
}

class _WebReferenceSurfaceState extends State<WebReferenceSurface> {
  late final BrowserWebRuntime _runtime;
  _WebReferenceSection _desktopSection = _WebReferenceSection.mixer;

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

  void _selectDesktopSection(_WebReferenceSection section) {
    if (_desktopSection == section || !mounted) {
      return;
    }
    setState(() {
      _desktopSection = section;
    });
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

        final operatorShell = WebReleaseShell(
          key: ValueKey(
            compact ? 'compact-web-operator-shell' : 'desktop-web-operator-shell',
          ),
          controller: _runtime.captureController,
          recordingController: _runtime.recordingController,
          fingerprintController: _runtime.fingerprintController,
          mixerController: _runtime.mixerController,
        );

        return Scaffold(
          key: const ValueKey('web-reference-shell'),
          backgroundColor: LiveMixTokens.surfaceBase,
          endDrawerEnableOpenDragGesture: false,
          endDrawer: compact
              ? SizedBox(
                  width: drawerWidth,
                  child: Drawer(
                    backgroundColor: LiveMixTokens.surfaceBase,
                    child: operatorShell,
                  ),
                )
              : null,
          body: Builder(
            builder: (scaffoldContext) {
              void openOperator() {
                if (compact) {
                  Scaffold.of(scaffoldContext).openEndDrawer();
                } else {
                  _selectDesktopSection(_WebReferenceSection.operator);
                }
              }

              return compact
                  ? _CompactReferenceBody(
                      liveState: liveState,
                      onOpenOperator: openOperator,
                    )
                  : _DesktopReferenceBody(
                      liveState: liveState,
                      section: _desktopSection,
                      operatorShell: operatorShell,
                      onSectionChanged: _selectDesktopSection,
                      onReprobe: () =>
                          unawaited(_runtime.captureController.probe()),
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
    required this.section,
    required this.operatorShell,
    required this.onSectionChanged,
    required this.onReprobe,
    required this.onOpenOperator,
    required this.onFaderChanged,
    required this.onMutedChanged,
    required this.onSoloChanged,
    required this.onToggleRecording,
  });

  final WebReferenceLiveState liveState;
  final _WebReferenceSection section;
  final Widget operatorShell;
  final ValueChanged<_WebReferenceSection> onSectionChanged;
  final VoidCallback onReprobe;
  final VoidCallback onOpenOperator;
  final ValueChanged<double> onFaderChanged;
  final ValueChanged<bool> onMutedChanged;
  final ValueChanged<bool> onSoloChanged;
  final VoidCallback onToggleRecording;

  @override
  Widget build(BuildContext context) {
    final mixerVisible = section == _WebReferenceSection.mixer;
    return Row(
      children: [
        _DesktopRail(
          section: section,
          onSectionChanged: onSectionChanged,
          onOpenOperator: onOpenOperator,
        ),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Offstage(
                offstage: !mixerVisible,
                child: WebLiveMixerReference(
                  liveState: liveState,
                  onFaderChanged: onFaderChanged,
                  onMutedChanged: onMutedChanged,
                  onSoloChanged: onSoloChanged,
                  onToggleRecording: onToggleRecording,
                  onOpenOperator: () =>
                      onSectionChanged(_WebReferenceSection.session),
                ),
              ),
              Offstage(
                offstage: mixerVisible,
                child: _DesktopOperatorSection(
                  section: section,
                  onReprobe: onReprobe,
                  child: operatorShell,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DesktopOperatorSection extends StatelessWidget {
  const _DesktopOperatorSection({
    required this.section,
    required this.onReprobe,
    required this.child,
  });

  final _WebReferenceSection section;
  final VoidCallback onReprobe;
  final Widget child;

  String get _title => switch (section) {
        _WebReferenceSection.patchbay => 'PATCHBAY',
        _WebReferenceSection.session => 'SESSION',
        _WebReferenceSection.settings => 'SETTINGS',
        _WebReferenceSection.operator => 'WEB OPERATOR',
        _WebReferenceSection.mixer => 'WEB OPERATOR',
      };

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: LiveMixTokens.surfaceBase,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 58),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: const BoxDecoration(
                color: LiveMixTokens.surfaceRack,
                border: Border(
                  bottom: BorderSide(color: LiveMixTokens.surfaceStrip),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _title,
                      style: LiveMixTextStyles.sectionDisplay.copyWith(
                        color: LiveMixTokens.textPrimary,
                      ),
                    ),
                  ),
                  if (section == _WebReferenceSection.settings)
                    OutlinedButton.icon(
                      onPressed: onReprobe,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('RE-PROBE CAPABILITIES'),
                    ),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _DesktopRail extends StatelessWidget {
  const _DesktopRail({
    required this.section,
    required this.onSectionChanged,
    required this.onOpenOperator,
  });

  final _WebReferenceSection section;
  final ValueChanged<_WebReferenceSection> onSectionChanged;
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
            _RailItem(
              label: 'Mixer',
              active: section == _WebReferenceSection.mixer,
              onPressed: () => onSectionChanged(_WebReferenceSection.mixer),
            ),
            _RailItem(
              label: 'Patchbay',
              active: section == _WebReferenceSection.patchbay,
              onPressed: () => onSectionChanged(_WebReferenceSection.patchbay),
            ),
            _RailItem(
              label: 'Session',
              active: section == _WebReferenceSection.session,
              onPressed: () => onSectionChanged(_WebReferenceSection.session),
            ),
            _RailItem(
              label: 'Settings',
              active: section == _WebReferenceSection.settings,
              onPressed: () => onSectionChanged(_WebReferenceSection.settings),
            ),
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
  const _RailItem({
    required this.label,
    required this.onPressed,
    this.active = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 58),
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
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: const Size(double.infinity, 58),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          foregroundColor: active
              ? LiveMixTokens.textPrimary
              : LiveMixTokens.textSecondary,
          shape: const RoundedRectangleBorder(),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: LiveMixTextStyles.uiLabel,
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
            liveSourceLabel: liveState.sourceLabel,
            liveSourceActive: liveState.captureActive,
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
