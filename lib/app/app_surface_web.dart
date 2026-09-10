import 'package:flutter/material.dart';

import '../design/live_mix_tokens.dart';

class WebReleaseShell extends StatelessWidget {
  const WebReleaseShell({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LiveMixTokens.surfaceBase,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: LiveMixTokens.surfaceRack,
                      border: Border.all(
                        color: LiveMixTokens.accentCopper,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'LIVEMIXMASTER',
                          style: LiveMixTextStyles.sectionDisplay,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            _statusBadge(
                              icon: Icons.language,
                              label: 'WEB AUDIO',
                              color: LiveMixTokens.accentCopper,
                            ),
                            _statusBadge(
                              icon: Icons.lock_outline,
                              label: 'SOURCE PERMISSION REQUIRED',
                              color: LiveMixTokens.statusWarn,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Browser capture is capability-driven. LiveMixMaster will only expose sources the current browser and operating system actually provide.',
                          style: LiveMixTextStyles.body.copyWith(
                            color: LiveMixTokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const _CapabilityPanel(),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: LiveMixTokens.surfaceStrip,
                      border: Border.all(color: LiveMixTokens.surfaceRack),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'W1 FOUNDATION — BROWSER CAPTURE, AUDIOWORKLET DSP AND LIVE ROUTING FOLLOW IN W2/W3.',
                      style: LiveMixTextStyles.uiLabel.copyWith(
                        color: LiveMixTokens.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _statusBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: LiveMixTokens.surfaceStrip,
          border: Border.all(color: color, width: 2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(label, style: LiveMixTextStyles.uiLabel),
          ],
        ),
      ),
    );
  }
}

class _CapabilityPanel extends StatelessWidget {
  const _CapabilityPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: LiveMixTokens.surfaceRack,
        border: Border.all(color: LiveMixTokens.surfaceStrip, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Column(
        children: [
          _CapabilityRow(
            icon: Icons.mic_none,
            label: 'MIC / USB INPUT',
            state: 'PERMISSION GATED',
            color: LiveMixTokens.accentCopper,
          ),
          SizedBox(height: 10),
          _CapabilityRow(
            icon: Icons.tab,
            label: 'TAB / WINDOW AUDIO',
            state: 'USER SELECTED',
            color: LiveMixTokens.accentOchre,
          ),
          SizedBox(height: 10),
          _CapabilityRow(
            icon: Icons.desktop_windows_outlined,
            label: 'SYSTEM AUDIO',
            state: 'BROWSER / OS DEPENDENT',
            color: LiveMixTokens.statusWarn,
          ),
        ],
      ),
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({
    required this.icon,
    required this.label,
    required this.state,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String state;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $state',
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: LiveMixTokens.surfaceStrip,
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: LiveMixTextStyles.uiLabel)),
            const SizedBox(width: 12),
            Text(
              state,
              textAlign: TextAlign.right,
              style: LiveMixTextStyles.numericTelemetry.copyWith(
                fontSize: 12,
                color: LiveMixTokens.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget buildPrimaryOperatorSurface() => const WebReleaseShell();
