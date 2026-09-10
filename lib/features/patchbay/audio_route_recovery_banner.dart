import 'package:flutter/material.dart';

import '../../audio/audio_engine_bridge.dart';
import '../../design/live_mix_tokens.dart';
import '../../design/widgets/lmm_controls.dart';

class AudioRouteRecoveryBanner extends StatelessWidget {
  const AudioRouteRecoveryBanner({
    super.key,
    required this.state,
    this.onRecoveryRequested,
  });

  final AudioRouteState state;
  final VoidCallback? onRecoveryRequested;

  @override
  Widget build(BuildContext context) {
    final presentation = _presentationFor(state);
    if (presentation == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: LiveMixTokens.surfaceStrip,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: presentation.color),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(presentation.icon, color: presentation.color),
          Text(
            presentation.status,
            style: LiveMixTextStyles.uiLabel.copyWith(
              color: presentation.color,
            ),
          ),
          Text(
            presentation.detail,
            style: LiveMixTextStyles.body.copyWith(
              color: LiveMixTokens.textSecondary,
            ),
          ),
          if (presentation.action case final action?)
            OutlinedButton(
              onPressed: onRecoveryRequested,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, LiveMixTokens.minimumTarget),
              ),
              child: Text(action),
            ),
        ],
      ),
    );
  }

  static _RoutePresentation? _presentationFor(AudioRouteState state) =>
      switch (state) {
        AudioRouteState.idle || AudioRouteState.active => null,
        AudioRouteState.preparing => const _RoutePresentation(
            status: 'CONNECTING AUDIO ROUTE',
            detail: 'Negotiating the selected Core Audio endpoint.',
            action: null,
            icon: Icons.sync,
            color: LiveMixTokens.statusWarn,
          ),
        AudioRouteState.noDevice => const _RoutePresentation(
            status: 'NO AUDIO INPUTS DETECTED',
            detail: 'Connect an input device or virtual loopback endpoint, then refresh.',
            action: 'REFRESH DEVICES',
            icon: Icons.device_unknown,
            color: LiveMixTokens.meterClip,
          ),
        AudioRouteState.permissionDenied => const _RoutePresentation(
            status: 'AUDIO INPUT PERMISSION DENIED',
            detail: 'Allow microphone/audio input access in macOS System Settings.',
            action: 'OPEN AUDIO SETTINGS',
            icon: Icons.lock_outline,
            color: LiveMixTokens.meterClip,
          ),
        AudioRouteState.noSignal => const _RoutePresentation(
            status: 'NO SIGNAL',
            detail: 'The route is open but no capture callbacks are advancing.',
            action: 'RETRY ROUTE',
            icon: Icons.signal_cellular_connected_no_internet_0_bar,
            color: LiveMixTokens.statusWarn,
          ),
        AudioRouteState.deviceLost => const _RoutePresentation(
            status: 'DEVICE LOST',
            detail: 'The selected endpoint disappeared from Core Audio.',
            action: 'REFRESH DEVICES',
            icon: Icons.link_off,
            color: LiveMixTokens.meterClip,
          ),
        AudioRouteState.formatError => const _RoutePresentation(
            status: 'FORMAT ERROR',
            detail: 'The endpoint format changed and the capture route must be renegotiated.',
            action: 'RECONNECT',
            icon: Icons.tune,
            color: LiveMixTokens.meterClip,
          ),
        AudioRouteState.overrun => const _RoutePresentation(
            status: 'AUDIO OVERRUN',
            detail: 'Capture timing exceeded the real-time budget; reconnect after checking load.',
            action: 'RECONNECT',
            icon: Icons.warning_amber_outlined,
            color: LiveMixTokens.meterClip,
          ),
        AudioRouteState.recovered => const _RoutePresentation(
            status: 'ROUTE RECOVERED',
            detail: 'Capture callbacks resumed on the selected endpoint.',
            action: null,
            icon: Icons.settings_backup_restore,
            color: LiveMixTokens.meterNominal,
          ),
        AudioRouteState.failed => const _RoutePresentation(
            status: 'AUDIO ROUTE FAILED',
            detail: 'The native capture route could not be started or restored.',
            action: 'RETRY ROUTE',
            icon: Icons.error_outline,
            color: LiveMixTokens.meterClip,
          ),
      };
}

class _RoutePresentation {
  const _RoutePresentation({
    required this.status,
    required this.detail,
    required this.action,
    required this.icon,
    required this.color,
  });

  final String status;
  final String detail;
  final String? action;
  final IconData icon;
  final Color color;
}
