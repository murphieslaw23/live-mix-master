import 'package:flutter/material.dart';

import '../../design/live_mix_tokens.dart';
import '../../design/widgets/lmm_controls.dart';

/// Compact field monitor for booth-side phone and tablet use.
class CompactMonitorView extends StatefulWidget {
  const CompactMonitorView({
    super.key,
    this.isStreaming = false,
    this.isRecording = false,
    this.currentTrackTitle = 'AWAITING TRACK DETECTION...',
    this.currentArtist = 'UNKNOWN ARTIST',
    this.streamBitrateKbps = 320.0,
    this.masterPeakLevel = 0.85,
  });

  final bool isStreaming;
  final bool isRecording;
  final String currentTrackTitle;
  final String currentArtist;
  final double streamBitrateKbps;
  final double masterPeakLevel;

  @override
  State<CompactMonitorView> createState() => _CompactMonitorViewState();
}

class _CompactMonitorViewState extends State<CompactMonitorView> {
  double _quickFader = 0.90;
  bool _limiterEngaged = false;

  @override
  Widget build(BuildContext context) {
    final peakDbfs = -60 + (widget.masterPeakLevel.clamp(0.0, 1.0) * 60);
    return Scaffold(
      backgroundColor: LiveMixTokens.surfaceBase,
      appBar: AppBar(
        backgroundColor: LiveMixTokens.surfaceRack,
        title: const Text('FIELD MONITOR', style: LiveMixTextStyles.uiLabel),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: LmmStatusBadge(
              label: 'BROADCAST',
              status: widget.isStreaming ? 'LIVE' : 'OFFLINE',
              detail: widget.isStreaming ? '${widget.streamBitrateKbps.toInt()} KBPS' : null,
              tone: widget.isStreaming ? LmmStatusTone.healthy : LmmStatusTone.neutral,
              icon: Icons.wifi_tethering,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildLiveTrackCard(),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: LiveMixTokens.surfaceRack,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: LiveMixTokens.textSecondary.withValues(alpha: .28)),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 560;
                      final meter = LmmStereoMeter(
                        label: 'MASTER',
                        leftDbfs: peakDbfs,
                        rightDbfs: peakDbfs - 1.5,
                      );
                      final fader = LmmFader(
                        label: 'MASTER ATTENUATION',
                        value: _quickFader,
                        onChanged: (value) => setState(() => _quickFader = value),
                      );

                      if (compact) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(child: meter),
                            const SizedBox(width: 16),
                            fader,
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(child: meter),
                          const SizedBox(width: 24),
                          fader,
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildStreamHealthFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveTrackCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LiveMixTokens.surfaceStrip,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: LiveMixTokens.accentCopper.withValues(alpha: .6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fingerprint, color: LiveMixTokens.accentCopper, size: 16),
              const SizedBox(width: 8),
              Text(
                'NOW PLAYING [ACOUSTID]',
                style: LiveMixTextStyles.uiLabel.copyWith(color: LiveMixTokens.accentCopper),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.currentTrackTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LiveMixTextStyles.uiLabel.copyWith(fontSize: 16),
          ),
          Text(
            widget.currentArtist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LiveMixTextStyles.body.copyWith(color: LiveMixTokens.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamHealthFooter() {
    return Row(
      children: [
        Expanded(
          child: LmmStatusBadge(
            label: 'BUFFER',
            status: '99.98%',
            detail: widget.isStreaming ? 'STABLE' : 'IDLE',
            tone: widget.isStreaming ? LmmStatusTone.healthy : LmmStatusTone.neutral,
            icon: Icons.network_check,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => setState(() => _limiterEngaged = !_limiterEngaged),
            child: LmmStatusBadge(
              label: 'SAFETY LIMITER',
              status: _limiterEngaged ? 'ENGAGED' : 'ARMED',
              detail: '-0.2 DB',
              tone: _limiterEngaged ? LmmStatusTone.warning : LmmStatusTone.healthy,
              icon: Icons.shield_outlined,
            ),
          ),
        ),
        if (widget.isRecording) ...[
          const SizedBox(width: 12),
          const LmmStatusBadge(
            label: 'RECORDING',
            status: 'ACTIVE',
            tone: LmmStatusTone.critical,
            icon: Icons.fiber_manual_record,
          ),
        ],
      ],
    );
  }
}
