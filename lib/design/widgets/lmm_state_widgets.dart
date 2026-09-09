import 'package:flutter/material.dart';

import '../live_mix_tokens.dart';
import 'lmm_controls.dart';

enum LmmRecordState {
  idle,
  recording,
  finalizing,
  finalized,
  writeFailure,
  diskFull,
}

class LmmRecordStatus extends StatelessWidget {
  const LmmRecordStatus({super.key, required this.state});

  final LmmRecordState state;

  static String copyFor(LmmRecordState state) => switch (state) {
        LmmRecordState.idle => 'IDLE',
        LmmRecordState.recording => 'RECORDING',
        LmmRecordState.finalizing => 'FINALIZING',
        LmmRecordState.finalized => 'FINALIZED',
        LmmRecordState.writeFailure => 'WRITE FAILURE',
        LmmRecordState.diskFull => 'DISK FULL',
      };

  (LmmStatusTone, IconData) get _presentation => switch (state) {
        LmmRecordState.idle => (LmmStatusTone.neutral, Icons.radio_button_unchecked),
        LmmRecordState.recording => (LmmStatusTone.critical, Icons.fiber_manual_record),
        LmmRecordState.finalizing => (LmmStatusTone.warning, Icons.sync),
        LmmRecordState.finalized => (LmmStatusTone.healthy, Icons.check_circle_outline),
        LmmRecordState.writeFailure => (LmmStatusTone.critical, Icons.save_as_outlined),
        LmmRecordState.diskFull => (LmmStatusTone.critical, Icons.sd_storage_outlined),
      };

  @override
  Widget build(BuildContext context) {
    final copy = copyFor(state);
    final (tone, icon) = _presentation;
    return Semantics(
      label: 'RECORD STATUS',
      value: copy,
      child: ExcludeSemantics(
        child: LmmStatusBadge(
          label: 'RECORD',
          status: copy,
          tone: tone,
          icon: icon,
        ),
      ),
    );
  }
}

enum LmmBroadcastState {
  offline,
  preflight,
  live,
  reconnecting,
  failed,
  invalidCredentials,
}

class LmmBroadcastStatus extends StatelessWidget {
  const LmmBroadcastStatus({super.key, required this.state});

  final LmmBroadcastState state;

  static String copyFor(LmmBroadcastState state) => switch (state) {
        LmmBroadcastState.offline => 'OFFLINE',
        LmmBroadcastState.preflight => 'PREFLIGHT',
        LmmBroadcastState.live => 'LIVE',
        LmmBroadcastState.reconnecting => 'RECONNECTING',
        LmmBroadcastState.failed => 'FAILED',
        LmmBroadcastState.invalidCredentials => 'INVALID CREDENTIALS',
      };

  (LmmStatusTone, IconData) get _presentation => switch (state) {
        LmmBroadcastState.offline => (LmmStatusTone.neutral, Icons.wifi_tethering_off),
        LmmBroadcastState.preflight => (LmmStatusTone.warning, Icons.fact_check_outlined),
        LmmBroadcastState.live => (LmmStatusTone.healthy, Icons.wifi_tethering),
        LmmBroadcastState.reconnecting => (LmmStatusTone.warning, Icons.sync),
        LmmBroadcastState.failed => (LmmStatusTone.critical, Icons.cloud_off_outlined),
        LmmBroadcastState.invalidCredentials => (LmmStatusTone.critical, Icons.key_off_outlined),
      };

  @override
  Widget build(BuildContext context) {
    final copy = copyFor(state);
    final (tone, icon) = _presentation;
    return Semantics(
      label: 'BROADCAST STATUS',
      value: copy,
      child: ExcludeSemantics(
        child: LmmStatusBadge(
          label: 'BROADCAST',
          status: copy,
          tone: tone,
          icon: icon,
        ),
      ),
    );
  }
}

enum LmmFingerprintState {
  searching,
  match,
  lowConfidence,
  noMatch,
  offlineLookup,
}

class LmmFingerprintHud extends StatelessWidget {
  const LmmFingerprintHud({
    super.key,
    required this.state,
    required this.artist,
    required this.title,
    required this.confidence,
    required this.provider,
    required this.timestamp,
  });

  final LmmFingerprintState state;
  final String artist;
  final String title;
  final double confidence;
  final String provider;
  final String timestamp;

  static String copyFor(LmmFingerprintState state) => switch (state) {
        LmmFingerprintState.searching => 'SEARCHING',
        LmmFingerprintState.match => 'MATCH',
        LmmFingerprintState.lowConfidence => 'LOW CONFIDENCE',
        LmmFingerprintState.noMatch => 'NO MATCH',
        LmmFingerprintState.offlineLookup => 'OFFLINE LOOKUP',
      };

  (Color, IconData) get _presentation => switch (state) {
        LmmFingerprintState.searching => (LiveMixTokens.accentCopper, Icons.fingerprint),
        LmmFingerprintState.match => (LiveMixTokens.meterNominal, Icons.verified_outlined),
        LmmFingerprintState.lowConfidence => (LiveMixTokens.statusWarn, Icons.help_outline),
        LmmFingerprintState.noMatch => (LiveMixTokens.meterClip, Icons.search_off),
        LmmFingerprintState.offlineLookup => (LiveMixTokens.statusWarn, Icons.cloud_off_outlined),
      };

  @override
  Widget build(BuildContext context) {
    final copy = copyFor(state);
    final (color, icon) = _presentation;
    return Semantics(
      label: 'FINGERPRINT $copy',
      value: '$artist · $title · ${(confidence * 100).round()} percent · $provider · $timestamp',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: LiveMixTokens.surfaceStrip,
            borderRadius: const BorderRadius.all(Radius.circular(4)),
            border: Border.all(color: color),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 18),
                  const SizedBox(width: 8),
                  Text(copy, style: LiveMixTextStyles.uiLabel.copyWith(color: color)),
                ],
              ),
              const SizedBox(height: 8),
              Text(artist, style: LiveMixTextStyles.uiLabel),
              Text(title, style: LiveMixTextStyles.body),
              const SizedBox(height: 6),
              Text(
                '$provider · ${(confidence * 100).round()}%',
                style: LiveMixTextStyles.numericTelemetry.copyWith(fontSize: 11),
              ),
              Text(
                timestamp,
                style: LiveMixTextStyles.numericTelemetry.copyWith(
                  color: LiveMixTokens.textSecondary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum LmmSessionRowState { approved, candidate, needsReview, ignored, disabled }

class LmmSessionRow extends StatelessWidget {
  const LmmSessionRow({
    super.key,
    required this.state,
    required this.artist,
    required this.title,
    this.onCorrect,
    this.onApprove,
    this.onIgnore,
  });

  final LmmSessionRowState state;
  final String artist;
  final String title;
  final VoidCallback? onCorrect;
  final VoidCallback? onApprove;
  final VoidCallback? onIgnore;

  static String copyFor(LmmSessionRowState state) => switch (state) {
        LmmSessionRowState.approved => 'APPROVED',
        LmmSessionRowState.candidate => 'CANDIDATE',
        LmmSessionRowState.needsReview => 'NEEDS REVIEW',
        LmmSessionRowState.ignored => 'IGNORED',
        LmmSessionRowState.disabled => 'DISABLED',
      };

  Color get _stateColor => switch (state) {
        LmmSessionRowState.approved => LiveMixTokens.meterNominal,
        LmmSessionRowState.candidate => LiveMixTokens.accentCopper,
        LmmSessionRowState.needsReview => LiveMixTokens.statusWarn,
        LmmSessionRowState.ignored => LiveMixTokens.textSecondary,
        LmmSessionRowState.disabled => LiveMixTokens.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    final disabled = state == LmmSessionRowState.disabled;
    final copy = copyFor(state);
    return Semantics(
      label: 'SESSION ROW $artist $title',
      value: copy,
      enabled: !disabled,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: LiveMixTokens.surfaceStrip,
          borderRadius: const BorderRadius.all(Radius.circular(4)),
          border: Border.all(color: _stateColor),
        ),
        child: Row(
          children: [
            Icon(Icons.library_music_outlined, color: _stateColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(artist, style: LiveMixTextStyles.uiLabel),
                  Text(title, style: LiveMixTextStyles.body),
                  Text(copy, style: LiveMixTextStyles.uiLabel.copyWith(color: _stateColor)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _action('CORRECT', Icons.edit_outlined, disabled ? null : onCorrect),
            const SizedBox(width: 6),
            _action('APPROVE', Icons.check, disabled ? null : onApprove),
            const SizedBox(width: 6),
            _action('IGNORE', Icons.block_outlined, disabled ? null : onIgnore),
          ],
        ),
      ),
    );
  }

  Widget _action(String label, IconData icon, VoidCallback? callback) => OutlinedButton.icon(
        onPressed: callback,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, LiveMixTokens.minimumTarget),
        ),
        icon: Icon(icon, size: 16),
        label: Text(label),
      );
}

enum LmmChannelStripState {
  defaultState,
  active,
  muted,
  solo,
  disabled,
  disconnected,
  clipping,
}

class LmmChannelStripStateBadge extends StatelessWidget {
  const LmmChannelStripStateBadge({
    super.key,
    required this.label,
    required this.state,
  });

  final String label;
  final LmmChannelStripState state;

  static String copyFor(LmmChannelStripState state) => switch (state) {
        LmmChannelStripState.defaultState => 'DEFAULT',
        LmmChannelStripState.active => 'ACTIVE',
        LmmChannelStripState.muted => 'MUTED',
        LmmChannelStripState.solo => 'SOLO',
        LmmChannelStripState.disabled => 'DISABLED',
        LmmChannelStripState.disconnected => 'DISCONNECTED',
        LmmChannelStripState.clipping => 'CLIPPING',
      };

  (LmmStatusTone, IconData) get _presentation => switch (state) {
        LmmChannelStripState.defaultState => (LmmStatusTone.neutral, Icons.tune),
        LmmChannelStripState.active => (LmmStatusTone.healthy, Icons.graphic_eq),
        LmmChannelStripState.muted => (LmmStatusTone.warning, Icons.volume_off_outlined),
        LmmChannelStripState.solo => (LmmStatusTone.healthy, Icons.hearing_outlined),
        LmmChannelStripState.disabled => (LmmStatusTone.neutral, Icons.pause_circle_outline),
        LmmChannelStripState.disconnected => (LmmStatusTone.critical, Icons.link_off),
        LmmChannelStripState.clipping => (LmmStatusTone.critical, Icons.warning_amber_outlined),
      };

  @override
  Widget build(BuildContext context) {
    final copy = copyFor(state);
    final (tone, icon) = _presentation;
    return LmmStatusBadge(
      label: label,
      status: copy,
      tone: tone,
      icon: icon,
    );
  }
}

class LmmTrimKnob extends StatelessWidget {
  const LmmTrimKnob({
    super.key,
    required this.label,
    required this.valueDb,
    required this.onChanged,
  });

  final String label;
  final double valueDb;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final value = valueDb.clamp(-18.0, 18.0).toDouble();
    return Semantics(
      label: label,
      value: '${value.toStringAsFixed(1)} dB',
      slider: true,
      enabled: onChanged != null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: LiveMixTokens.minimumTarget,
          minHeight: LiveMixTokens.minimumTarget,
        ),
        child: SizedBox(
          width: 132,
          height: 64,
          child: Slider(
            value: value,
            min: -18,
            max: 18,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

enum LmmMasterBusState { defaultState, limiterOn, clipping }

class LmmMasterBusStatus extends StatelessWidget {
  const LmmMasterBusStatus({
    super.key,
    required this.state,
    required this.loudnessLufs,
    required this.truePeakDbtp,
  });

  final LmmMasterBusState state;
  final double loudnessLufs;
  final double truePeakDbtp;

  static String copyFor(LmmMasterBusState state) => switch (state) {
        LmmMasterBusState.defaultState => 'LIMITER READY',
        LmmMasterBusState.limiterOn => 'LIMITER ON',
        LmmMasterBusState.clipping => 'CLIPPING',
      };

  @override
  Widget build(BuildContext context) {
    final copy = copyFor(state);
    final clipping = state == LmmMasterBusState.clipping;
    return Semantics(
      label: 'MASTER BUS',
      value: '$copy · ${loudnessLufs.toStringAsFixed(1)} LUFS · ${truePeakDbtp.toStringAsFixed(1)} dBTP',
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: LiveMixTokens.surfaceStrip,
          borderRadius: const BorderRadius.all(Radius.circular(4)),
          border: Border.all(
            color: clipping ? LiveMixTokens.meterClip : LiveMixTokens.accentCopper,
          ),
        ),
        child: Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(
              clipping ? Icons.warning_amber_outlined : Icons.shield_outlined,
              color: clipping ? LiveMixTokens.meterClip : LiveMixTokens.accentCopper,
            ),
            Text(copy, style: LiveMixTextStyles.uiLabel),
            Text('${loudnessLufs.toStringAsFixed(1)} LUFS', style: LiveMixTextStyles.numericTelemetry),
            Text('${truePeakDbtp.toStringAsFixed(1)} dBTP', style: LiveMixTextStyles.numericTelemetry),
          ],
        ),
      ),
    );
  }
}
