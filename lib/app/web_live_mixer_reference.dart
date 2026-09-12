import 'package:flutter/material.dart';

import '../design/live_mix_tokens.dart';
import '../design/widgets/lmm_controls.dart';
import 'web_reference_live_state.dart';

/// Desktop reference composition backed only by verified W5 browser state.
///
/// The historical [MixerDeskView] remains the deterministic design fixture used
/// by golden tests. This production Web view deliberately renders unavailable
/// values instead of inheriting fixture telemetry for measurements that the Web
/// runtime does not currently produce.
class WebLiveMixerReference extends StatelessWidget {
  const WebLiveMixerReference({
    super.key,
    required this.liveState,
    this.onFaderChanged,
    this.onMutedChanged,
    this.onSoloChanged,
    this.onToggleRecording,
    this.onOpenOperator,
  });

  final WebReferenceLiveState liveState;
  final ValueChanged<double>? onFaderChanged;
  final ValueChanged<bool>? onMutedChanged;
  final ValueChanged<bool>? onSoloChanged;
  final VoidCallback? onToggleRecording;
  final VoidCallback? onOpenOperator;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LiveMixTokens.surfaceBase,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            _buildFingerprintBanner(),
            _buildFingerprintPanel(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildLiveChannel(),
                          const SizedBox(width: 12),
                          _buildUnassignedChannel(2),
                          const SizedBox(width: 12),
                          _buildUnassignedChannel(3),
                          const SizedBox(width: 12),
                          _buildUnassignedChannel(4),
                        ],
                      ),
                    ),
                  ),
                  _buildMasterSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: const BoxDecoration(
        color: LiveMixTokens.surfaceRack,
        border: Border(
          bottom: BorderSide(color: LiveMixTokens.surfaceStrip, width: 2),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: LiveMixTokens.accentOchre,
              borderRadius: BorderRadius.all(Radius.circular(4)),
            ),
            child: Text(
              'LMM',
              style: LiveMixTextStyles.uiLabel.copyWith(
                color: LiveMixTokens.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Text('LIVEMIXMASTER', style: LiveMixTextStyles.sectionDisplay),
          const SizedBox(width: 12),
          const LmmStatusBadge(
            label: 'ENGINE',
            status: 'BROWSER AUDIO',
            tone: LmmStatusTone.neutral,
            icon: Icons.graphic_eq,
          ),
          const Spacer(),
          if (liveState.recordingActive) ...[
            const LmmStatusBadge(
              label: 'RECORDING',
              status: 'ACTIVE',
              detail: 'WAV',
              tone: LmmStatusTone.critical,
              icon: Icons.fiber_manual_record,
            ),
            const SizedBox(width: 8),
          ],
          LmmToggleControl(
            label: 'RECORD',
            value: liveState.recordingActive,
            onChanged: liveState.captureActive && onToggleRecording != null
                ? (_) => onToggleRecording!()
                : null,
          ),
          const SizedBox(width: 8),
          const LmmStatusBadge(
            label: 'BROADCAST',
            status: 'UNAVAILABLE',
            tone: LmmStatusTone.neutral,
            icon: Icons.portable_wifi_off,
          ),
          if (onOpenOperator != null) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'WEB OPERATOR',
              onPressed: onOpenOperator,
              constraints: const BoxConstraints(
                minWidth: LiveMixTokens.minimumTarget,
                minHeight: LiveMixTokens.minimumTarget,
              ),
              icon: const Icon(Icons.tune_rounded),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFingerprintBanner() {
    final matched = liveState.matchConfidence != null;
    return Container(
      width: double.infinity,
      color: LiveMixTokens.surfaceStrip,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          const Icon(
            Icons.fingerprint,
            color: LiveMixTokens.accentCopper,
            size: 20,
          ),
          const SizedBox(width: 10),
          Text(
            matched ? 'LIVE TRACK:' : 'LIVE TRACK:',
            style: LiveMixTextStyles.uiLabel.copyWith(
              color: LiveMixTokens.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              matched
                  ? '${liveState.currentArtist.toUpperCase()} — ${liveState.currentTrackTitle.toUpperCase()}'
                  : liveState.currentTrackTitle,
              overflow: TextOverflow.ellipsis,
              style: LiveMixTextStyles.uiLabel,
            ),
          ),
          if (liveState.matchConfidence case final confidence?)
            Text(
              'CONFIDENCE: ${(confidence.clamp(0.0, 1.0) * 100).round()}%',
              style: LiveMixTextStyles.numericTelemetry.copyWith(
                color: LiveMixTokens.accentCopper,
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFingerprintPanel() {
    final confidence = liveState.matchConfidence == null
        ? 'N/A'
        : '${(liveState.matchConfidence!.clamp(0.0, 1.0) * 100).round()}%';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LiveMixTokens.surfaceRack,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: LiveMixTokens.accentCopper.withValues(alpha: .55),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.fingerprint, color: LiveMixTokens.accentCopper, size: 26),
          const SizedBox(width: 12),
          Expanded(child: _field('ARTIST', liveState.currentArtist)),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: _field('TITLE', liveState.currentTrackTitle)),
          const SizedBox(width: 12),
          SizedBox(width: 92, child: _field('MATCH', confidence)),
          const SizedBox(width: 16),
          OutlinedButton.icon(
            onPressed: onOpenOperator,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, LiveMixTokens.minimumTarget),
            ),
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('CORRECT'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onOpenOperator,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, LiveMixTokens.minimumTarget),
            ),
            icon: const Icon(Icons.playlist_play_outlined, size: 16),
            label: const Text('VIEW SESSION'),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveChannel() {
    final meterDbfs = _linearPeakToDbfs(liveState.channelPeak);
    return _channelShell(
      title: 'BROWSER INPUT',
      source: liveState.sourceLabel,
      active: liveState.captureActive,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LmmDeviceStatus(
            label: liveState.sourceLabel,
            state: liveState.captureActive
                ? (liveState.muted ? LmmDeviceState.muted : LmmDeviceState.active)
                : LmmDeviceState.noSignal,
          ),
          const SizedBox(height: 8),
          _channelMeter(meterDbfs),
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: LmmFader(
                    label: 'FADER',
                    value: liveState.fader,
                    onChanged: liveState.mixerEnabled ? onFaderChanged : null,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 74,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      LmmToggleControl(
                        label: 'MUTE',
                        value: liveState.muted,
                        onChanged: liveState.mixerEnabled ? onMutedChanged : null,
                      ),
                      const SizedBox(height: 8),
                      LmmToggleControl(
                        label: 'SOLO',
                        value: liveState.solo,
                        onChanged: liveState.mixerEnabled ? onSoloChanged : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnassignedChannel(int index) {
    return _channelShell(
      title: 'UNASSIGNED $index',
      source: 'NO ROUTE',
      active: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LmmDeviceStatus(
            label: 'NO ACTIVE SOURCE',
            state: LmmDeviceState.noSignal,
          ),
          const SizedBox(height: 8),
          _channelMeter(-60),
          const SizedBox(height: 10),
          const Expanded(
            child: LmmFader(label: 'FADER', value: 0, onChanged: null),
          ),
        ],
      ),
    );
  }

  Widget _channelShell({
    required String title,
    required String source,
    required bool active,
    required Widget child,
  }) {
    return Container(
      width: 230,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LiveMixTokens.surfaceRack,
        border: Border.all(
          color: active
              ? LiveMixTokens.accentCopper
              : LiveMixTokens.surfaceStrip,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: LiveMixTextStyles.uiLabel),
          const SizedBox(height: 2),
          Text(
            source,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: LiveMixTextStyles.body.copyWith(
              color: LiveMixTokens.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _channelMeter(double dbfs) {
    final normalized = ((dbfs.clamp(-60.0, 0.0) + 60.0) / 60.0).toDouble();
    final color = dbfs >= -6
        ? LiveMixTokens.meterClip
        : dbfs >= -12
            ? LiveMixTokens.meterHeadroom
            : LiveMixTokens.meterNominal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(
          value: normalized,
          minHeight: 8,
          backgroundColor: LiveMixTokens.meterInactive,
          color: color,
        ),
        const SizedBox(height: 4),
        Text(
          '${dbfs.toStringAsFixed(1)} dBFS',
          style: LiveMixTextStyles.numericTelemetry.copyWith(fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildMasterSection() {
    final leftDbfs = _linearPeakToDbfs(liveState.masterPeakLeft);
    final rightDbfs = _linearPeakToDbfs(liveState.masterPeakRight);
    return Container(
      width: 300,
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: LiveMixTokens.surfaceRack,
        border: Border(left: BorderSide(color: LiveMixTokens.surfaceStrip, width: 2)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'MASTER BUS',
              style: LiveMixTextStyles.sectionDisplay.copyWith(
                color: LiveMixTokens.accentOchre,
              ),
            ),
            const SizedBox(height: 12),
            LmmStereoMeter(
              label: 'MASTER STEREO',
              leftDbfs: leftDbfs,
              rightDbfs: rightDbfs,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _telemetryCell('LOUDNESS', 'N/A')),
                const SizedBox(width: 6),
                Expanded(child: _telemetryCell('TRUE PEAK', 'N/A')),
              ],
            ),
            const SizedBox(height: 6),
            _telemetryCell(
              'LIMITER',
              liveState.mixerEnabled
                  ? (liveState.limiterActive ? 'ON' : 'OFF')
                  : 'N/A',
            ),
            const SizedBox(height: 12),
            const LmmStatusBadge(
              label: 'BROADCAST',
              status: 'UNAVAILABLE',
              tone: LmmStatusTone.neutral,
              icon: Icons.portable_wifi_off,
            ),
            const SizedBox(height: 12),
            LmmStatusBadge(
              label: 'CAPTURE',
              status: liveState.captureActive ? 'ACTIVE' : 'IDLE',
              detail: liveState.captureActive ? liveState.sourceLabel : null,
              tone: liveState.captureActive
                  ? LmmStatusTone.healthy
                  : LmmStatusTone.neutral,
              icon: liveState.captureActive
                  ? Icons.mic_none_outlined
                  : Icons.mic_off_outlined,
            ),
          ],
        ),
      ),
    );
  }

  Widget _telemetryCell(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: const BoxDecoration(
        color: LiveMixTokens.surfaceStrip,
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: LiveMixTextStyles.uiLabel),
          const SizedBox(height: 2),
          Text(value, style: LiveMixTextStyles.numericTelemetry),
        ],
      ),
    );
  }

  Widget _field(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: LiveMixTextStyles.uiLabel),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: LiveMixTextStyles.body.copyWith(color: LiveMixTokens.textPrimary),
        ),
      ],
    );
  }

  double _linearPeakToDbfs(double peak) {
    final clamped = peak.clamp(0.0, 1.0).toDouble();
    if (clamped <= 0) return -60;
    return -60 + (clamped * 60);
  }
}
