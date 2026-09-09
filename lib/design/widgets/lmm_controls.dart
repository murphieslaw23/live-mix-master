import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../live_mix_tokens.dart';

enum LmmStatusTone { healthy, neutral, warning, critical }

enum LmmDeviceState { connected, disconnected, lost }

enum LmmPreflightState { ready, pending, warning, error }

class LmmToggleControl extends StatefulWidget {
  const LmmToggleControl({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  State<LmmToggleControl> createState() => _LmmToggleControlState();
}

class _LmmToggleControlState extends State<LmmToggleControl> {
  final FocusNode _focusNode = FocusNode();

  bool get _enabled => widget.onChanged != null;

  void _activate() {
    if (!_enabled) return;
    widget.onChanged!(!widget.value);
  }

  void _tap() {
    _focusNode.requestFocus();
    _activate();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stateLabel = widget.value ? 'ON' : 'OFF';
    final foreground = _enabled
        ? LiveMixTokens.textPrimary
        : LiveMixTokens.textSecondary.withValues(alpha: LiveMixTokens.disabledOpacity);
    final background = widget.value
        ? LiveMixTokens.accentOchre.withValues(alpha: .22)
        : LiveMixTokens.surfaceStrip;

    return Semantics(
      label: widget.label,
      value: stateLabel,
      button: true,
      enabled: _enabled,
      onTap: _enabled ? _tap : null,
      child: ExcludeSemantics(
        child: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.enter): _activate,
            const SingleActivator(LogicalKeyboardKey.space): _activate,
          },
          child: Focus(
            focusNode: _focusNode,
            canRequestFocus: _enabled,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _enabled ? _tap : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: LiveMixTokens.minimumTarget,
                  minHeight: LiveMixTokens.minimumTarget,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: const BorderRadius.all(Radius.circular(4)),
                    border: Border.all(
                      color: widget.value ? LiveMixTokens.accentOchre : LiveMixTokens.textSecondary,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Center(
                      child: Text(
                        '${widget.label} $stateLabel',
                        style: LiveMixTextStyles.uiLabel.copyWith(color: foreground),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LmmStatusBadge extends StatelessWidget {
  const LmmStatusBadge({
    super.key,
    required this.label,
    required this.status,
    required this.tone,
    required this.icon,
    this.detail,
  });

  final String label;
  final String status;
  final String? detail;
  final LmmStatusTone tone;
  final IconData icon;

  Color get _toneColor => switch (tone) {
        LmmStatusTone.healthy => LiveMixTokens.meterNominal,
        LmmStatusTone.neutral => LiveMixTokens.textSecondary,
        LmmStatusTone.warning => LiveMixTokens.statusWarn,
        LmmStatusTone.critical => LiveMixTokens.meterClip,
      };

  @override
  Widget build(BuildContext context) {
    final semanticValue = detail == null ? status : '$status · $detail';
    return Semantics(
      label: label,
      value: semanticValue,
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: LiveMixTokens.minimumTarget),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: LiveMixTokens.surfaceStrip,
            borderRadius: const BorderRadius.all(Radius.circular(4)),
            border: Border.all(color: _toneColor),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(icon, size: 18, color: _toneColor),
              Text(label, style: LiveMixTextStyles.uiLabel),
              Text(status, style: LiveMixTextStyles.uiLabel.copyWith(color: _toneColor)),
              if (detail case final detail?)
                Text(detail, style: LiveMixTextStyles.body.copyWith(color: LiveMixTokens.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

class LmmStereoMeter extends StatelessWidget {
  const LmmStereoMeter({
    super.key,
    required this.label,
    required this.leftDbfs,
    required this.rightDbfs,
  });

  final String label;
  final double leftDbfs;
  final double rightDbfs;

  double _normalized(double dbfs) => ((dbfs.clamp(-60.0, 0.0) + 60.0) / 60.0).toDouble();

  Color _meterColor(double dbfs) {
    if (dbfs >= -6) return LiveMixTokens.meterClip;
    if (dbfs >= -12) return LiveMixTokens.meterHeadroom;
    return LiveMixTokens.meterNominal;
  }

  Widget _channel(String channel, double dbfs) {
    final value = '${dbfs.toStringAsFixed(1)} dBFS';
    return Semantics(
      label: '$label $channel meter',
      value: value,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(
              value: _normalized(dbfs),
              minHeight: 8,
              backgroundColor: LiveMixTokens.meterInactive,
              color: _meterColor(dbfs),
            ),
            const SizedBox(height: 4),
            Text(value, style: LiveMixTextStyles.numericTelemetry),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 220),
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: LiveMixTokens.surfaceRack,
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: LiveMixTextStyles.uiLabel),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final tick in LiveMixTokens.meterScaleDbfs)
                Text('${tick.toInt()}', style: LiveMixTextStyles.uiLabel.copyWith(color: LiveMixTokens.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          _channel('left', leftDbfs),
          const SizedBox(height: 8),
          _channel('right', rightDbfs),
        ],
      ),
    );
  }
}

class LmmDeviceStatus extends StatelessWidget {
  const LmmDeviceStatus({super.key, required this.label, required this.state});

  final String label;
  final LmmDeviceState state;

  (String, IconData, Color) get _presentation => switch (state) {
        LmmDeviceState.connected => ('CONNECTED', Icons.link, LiveMixTokens.meterNominal),
        LmmDeviceState.disconnected => ('DISCONNECTED', Icons.link_off, LiveMixTokens.statusWarn),
        LmmDeviceState.lost => ('DEVICE LOST', Icons.link_off, LiveMixTokens.meterClip),
      };

  @override
  Widget build(BuildContext context) {
    final (status, icon, color) = _presentation;
    return Semantics(
      label: label,
      value: status,
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: LiveMixTokens.minimumTarget),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Text(label, style: LiveMixTextStyles.uiLabel),
              const SizedBox(width: 8),
              Text(status, style: LiveMixTextStyles.uiLabel.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

class LmmPreflightCheck extends StatelessWidget {
  const LmmPreflightCheck({
    super.key,
    required this.label,
    required this.state,
    this.detail,
  });

  final String label;
  final LmmPreflightState state;
  final String? detail;

  (String, IconData, Color) get _presentation => switch (state) {
        LmmPreflightState.ready => ('READY', Icons.check_circle_outline, LiveMixTokens.meterNominal),
        LmmPreflightState.pending => ('PENDING', Icons.pending_outlined, LiveMixTokens.textSecondary),
        LmmPreflightState.warning => ('WARNING', Icons.warning_amber_outlined, LiveMixTokens.statusWarn),
        LmmPreflightState.error => ('ERROR', Icons.error_outline, LiveMixTokens.meterClip),
      };

  @override
  Widget build(BuildContext context) {
    final (status, icon, color) = _presentation;
    final semanticValue = detail == null ? status : '$status · $detail';
    return Semantics(
      label: label,
      value: semanticValue,
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: LiveMixTokens.minimumTarget),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Text(label, style: LiveMixTextStyles.uiLabel),
              const SizedBox(width: 8),
              Text(status, style: LiveMixTextStyles.uiLabel.copyWith(color: color)),
              if (detail case final detail?) ...[
                const SizedBox(width: 8),
                Text(detail, style: LiveMixTextStyles.body.copyWith(color: LiveMixTokens.textSecondary)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class LmmFader extends StatelessWidget {
  const LmmFader({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final clampedValue = value.clamp(0.0, 1.0).toDouble();
    final percent = (clampedValue * 100).round();
    return Semantics(
      label: label,
      value: '$percent percent',
      slider: true,
      enabled: onChanged != null,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: LiveMixTokens.minimumTarget),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: LiveMixTextStyles.uiLabel),
              SizedBox(
                width: LiveMixTokens.minimumTarget,
                height: 180,
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Slider(
                    value: clampedValue,
                    min: 0,
                    max: 1,
                    onChanged: onChanged,
                  ),
                ),
              ),
              Text('$percent%', style: LiveMixTextStyles.numericTelemetry),
            ],
          ),
        ),
      ),
    );
  }
}
