import 'package:flutter/material.dart';

import '../../design/live_mix_tokens.dart';
import '../../design/widgets/lmm_controls.dart';

/// Read-only booth/field monitor matching the approved Issue #1 mobile baseline.
class CompactMonitorView extends StatelessWidget {
  const CompactMonitorView({
    super.key,
    this.isStreaming = false,
    this.broadcastConfigured = false,
    this.isRecording = false,
    this.currentTrackTitle = 'AWAITING TRACK DETECTION...',
    this.currentArtist = 'UNKNOWN ARTIST',
    this.streamBitrateKbps,
    this.masterPeakLevel = 0,
    this.matchConfidence,
    this.loudnessLufs,
    this.truePeakDbtp,
    this.limiterActive,
  });

  final bool isStreaming;
  final bool broadcastConfigured;
  final bool isRecording;
  final String currentTrackTitle;
  final String currentArtist;
  final double? streamBitrateKbps;
  final double masterPeakLevel;
  final double? matchConfidence;
  final double? loudnessLufs;
  final double? truePeakDbtp;
  final bool? limiterActive;

  @override
  Widget build(BuildContext context) {
    final peakDbfs = -60 + (masterPeakLevel.clamp(0.0, 1.0) * 60);

    return Scaffold(
      backgroundColor: LiveMixTokens.surfaceBase,
      body: SafeArea(
        child: Column(
          children: [
            _buildBrandHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildMonitorHeading(),
                    const SizedBox(height: 10),
                    _buildMasterCard(peakDbfs),
                    if (isRecording || broadcastConfigured) ...[
                      const SizedBox(height: 10),
                      _buildRecoveryRow(),
                    ],
                    const SizedBox(height: 10),
                    _buildCurrentTrackCard(),
                    const SizedBox(height: 10),
                    _buildSourceStatusCard(),
                  ],
                ),
              ),
            ),
            _buildBottomNavigation(),
          ],
        ),
      ),
    );
  }

  Widget _buildBrandHeader() {
    final broadcastKnown = broadcastConfigured;
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(
        color: LiveMixTokens.surfaceRack,
        border: Border(
          bottom: BorderSide(color: LiveMixTokens.surfaceStrip, width: 2),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: LiveMixTokens.accentOchre,
              borderRadius: BorderRadius.all(Radius.circular(4)),
            ),
            child: Text(
              'LMM',
              style: LiveMixTextStyles.uiLabel.copyWith(color: LiveMixTokens.textPrimary),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('LIVEMIXMASTER', style: LiveMixTextStyles.uiLabel),
                Text('WAREHOUSE 023', style: LiveMixTextStyles.numericTelemetry),
              ],
            ),
          ),
          Icon(
            broadcastKnown && isStreaming
                ? Icons.wifi_tethering
                : broadcastKnown
                    ? Icons.wifi_tethering_off
                    : Icons.portable_wifi_off,
            color: broadcastKnown
                ? (isStreaming ? LiveMixTokens.meterNominal : LiveMixTokens.statusWarn)
                : LiveMixTokens.textSecondary,
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildMonitorHeading() {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: Text('FIELD MONITOR', style: LiveMixTextStyles.sectionDisplay)),
        Text('Read-only monitor', style: LiveMixTextStyles.body),
      ],
    );
  }

  Widget _buildMasterCard(double peakDbfs) {
    final bitrate = streamBitrateKbps == null ? 'N/A' : '${streamBitrateKbps!.toInt()} KBPS';
    final loudness = loudnessLufs == null ? 'N/A' : '${loudnessLufs!.toStringAsFixed(1)} LUFS';
    final truePeak = truePeakDbtp == null ? 'N/A' : '${truePeakDbtp!.toStringAsFixed(1)} dBTP';
    final limiter = limiterActive == null ? 'N/A' : (limiterActive! ? 'ON' : 'OFF');

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: LiveMixTokens.surfaceRack,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: LiveMixTokens.textSecondary.withValues(alpha: .28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'MASTER STEREO',
                style: LiveMixTextStyles.uiLabel.copyWith(color: LiveMixTokens.accentOchre),
              ),
              const Spacer(),
              Text(
                bitrate,
                style: LiveMixTextStyles.numericTelemetry.copyWith(
                  color: LiveMixTokens.textSecondary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildMeterRow('L', peakDbfs),
          const SizedBox(height: 5),
          _buildMeterRow('R', peakDbfs - 1.5),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final tick in LiveMixTokens.meterScaleDbfs)
                Text(
                  '${tick.toInt()}',
                  style: LiveMixTextStyles.numericTelemetry.copyWith(
                    color: LiveMixTokens.textSecondary,
                    fontSize: 8,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _telemetryCell('LOUDNESS', loudness)),
              const SizedBox(width: 6),
              Expanded(child: _telemetryCell('TRUE PEAK', truePeak)),
              const SizedBox(width: 6),
              Expanded(child: _telemetryCell('LIMITER', limiter)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMeterRow(String channel, double dbfs) {
    final normalized = ((dbfs.clamp(-60.0, 0.0) + 60.0) / 60.0).toDouble();
    final color = dbfs >= -6
        ? LiveMixTokens.meterClip
        : dbfs >= -12
            ? LiveMixTokens.meterHeadroom
            : LiveMixTokens.meterNominal;

    return Semantics(
      label: 'MASTER $channel meter',
      value: '${dbfs.toStringAsFixed(1)} dBFS',
      child: ExcludeSemantics(
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: Text(channel, style: LiveMixTextStyles.uiLabel),
            ),
            Expanded(
              child: LinearProgressIndicator(
                value: normalized,
                minHeight: 8,
                backgroundColor: LiveMixTokens.meterInactive,
                color: color,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 52,
              child: Text(
                dbfs.toStringAsFixed(1),
                textAlign: TextAlign.right,
                style: LiveMixTextStyles.numericTelemetry.copyWith(fontSize: 9),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _telemetryCell(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      decoration: const BoxDecoration(
        color: LiveMixTokens.surfaceStrip,
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: LiveMixTextStyles.uiLabel),
          Text(value, style: LiveMixTextStyles.numericTelemetry.copyWith(fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildRecoveryRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final recording = LmmStatusBadge(
          label: 'RECORDING',
          status: isRecording ? 'ACTIVE' : 'IDLE',
          detail: isRecording ? 'WAV' : null,
          tone: isRecording ? LmmStatusTone.critical : LmmStatusTone.neutral,
          icon: Icons.fiber_manual_record,
        );
        final bitrate = streamBitrateKbps == null ? null : '${streamBitrateKbps!.toInt()} KBPS';
        final broadcast = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LmmStatusBadge(
              label: 'BROADCAST',
              status: !broadcastConfigured
                  ? 'UNAVAILABLE'
                  : isStreaming
                      ? 'LIVE'
                      : 'OFFLINE',
              detail: broadcastConfigured && isStreaming ? bitrate : null,
              tone: !broadcastConfigured
                  ? LmmStatusTone.neutral
                  : isStreaming
                      ? LmmStatusTone.healthy
                      : LmmStatusTone.warning,
              icon: !broadcastConfigured
                  ? Icons.portable_wifi_off
                  : isStreaming
                      ? Icons.wifi_tethering
                      : Icons.wifi_tethering_off,
            ),
            if (broadcastConfigured && !isStreaming && isRecording)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  'Local recording continues',
                  style: LiveMixTextStyles.body.copyWith(
                    color: LiveMixTokens.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        );

        if (constraints.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              recording,
              const SizedBox(height: 8),
              broadcast,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: recording),
            const SizedBox(width: 10),
            Expanded(child: broadcast),
          ],
        );
      },
    );
  }

  Widget _buildCurrentTrackCard() {
    final confidence = matchConfidence == null ? 'N/A' : '${(matchConfidence!.clamp(0.0, 1.0) * 100).round()}%';
    return Container(
      padding: const EdgeInsets.all(10),
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
              const SizedBox(width: 7),
              Text(
                'CURRENT TRACK',
                style: LiveMixTextStyles.uiLabel.copyWith(color: LiveMixTokens.accentCopper),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _trackField('ARTIST', currentArtist)),
              const SizedBox(width: 8),
              Expanded(child: _trackField('TITLE', currentTrackTitle)),
              const SizedBox(width: 8),
              SizedBox(width: 62, child: _trackField('MATCH', confidence)),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _trackField(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: LiveMixTextStyles.uiLabel),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: LiveMixTextStyles.body.copyWith(fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildSourceStatusCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        color: LiveMixTokens.surfaceRack,
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      child: const Column(
        children: [
          LmmDeviceStatus(label: 'USB 1-2', state: LmmDeviceState.active),
          LmmDeviceStatus(label: 'REKORDBOX', state: LmmDeviceState.active),
          LmmDeviceStatus(label: 'MIC 1', state: LmmDeviceState.muted),
          LmmDeviceStatus(label: 'AUX', state: LmmDeviceState.noSignal),
        ],
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return Container(
      height: 50,
      decoration: const BoxDecoration(
        color: LiveMixTokens.surfaceRack,
        border: Border(top: BorderSide(color: LiveMixTokens.surfaceStrip, width: 2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _navItem('MONITOR', Icons.monitor_heart_outlined, active: true),
          ),
          const VerticalDivider(width: 1, color: LiveMixTokens.surfaceStrip),
          Expanded(
            child: _navItem('SESSION', Icons.playlist_play_outlined, active: false),
          ),
        ],
      ),
    );
  }

  Widget _navItem(String label, IconData icon, {required bool active}) {
    final color = active ? LiveMixTokens.accentOchre : LiveMixTokens.textSecondary;
    return Semantics(
      label: label,
      selected: active,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 7),
          Text(label, style: LiveMixTextStyles.uiLabel.copyWith(color: color)),
        ],
      ),
    );
  }
}
