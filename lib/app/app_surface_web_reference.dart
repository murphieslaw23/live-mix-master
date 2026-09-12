import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/live_mix_tokens.dart';
import '../design/web_reference_tokens.dart';
import '../features/mixer/mixer_desk_view.dart';
import '../features/monitor/compact_monitor_view.dart';
import 'app_surface_web.dart' show WebReleaseShell;

Widget buildPrimaryOperatorSurface() => const WebReferenceSurface();

/// Responsive web composition that makes the approved Issue #1/Picsart
/// mixer and field-monitor baselines the primary Vercel presentation.
///
/// The existing W5 [WebReleaseShell] remains intact inside an operator drawer
/// so capture, DSP, recording, fingerprint and durable-session behavior are
/// not rewritten as part of this visual-parity change.
class WebReferenceSurface extends StatelessWidget {
  const WebReferenceSurface({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < WebReferenceTokens.compactBreakpoint;
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
            child: const Drawer(
              backgroundColor: LiveMixTokens.surfaceBase,
              child: WebReleaseShell(),
            ),
          ),
          body: Builder(
            builder: (scaffoldContext) {
              void openOperator() => Scaffold.of(scaffoldContext).openEndDrawer();
              return compact
                  ? _CompactReferenceBody(onOpenOperator: openOperator)
                  : _DesktopReferenceBody(onOpenOperator: openOperator);
            },
          ),
        );
      },
    );
  }
}

class _DesktopReferenceBody extends StatelessWidget {
  const _DesktopReferenceBody({required this.onOpenOperator});

  final VoidCallback onOpenOperator;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _DesktopRail(onOpenOperator: onOpenOperator),
        const Expanded(child: MixerDeskView()),
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
          color: active ? LiveMixTokens.textPrimary : LiveMixTokens.textSecondary,
        ),
      ),
    );
  }
}

class _CompactReferenceBody extends StatelessWidget {
  const _CompactReferenceBody({required this.onOpenOperator});

  final VoidCallback onOpenOperator;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: CompactMonitorView(
            isStreaming: false,
            isRecording: true,
            currentTrackTitle: 'FORWARD THE REVOLUTION',
            currentArtist: 'SPIRAL TRIBE',
            streamBitrateKbps: 320,
            masterPeakLevel: .84,
            matchConfidence: .94,
            loudnessLufs: -14.2,
            truePeakDbtp: -6.0,
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
                backgroundColor: LiveMixTokens.surfaceRack.withValues(alpha: .94),
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
