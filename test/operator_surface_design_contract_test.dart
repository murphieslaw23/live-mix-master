import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('operator surfaces use the shared design system', () {
    final mixer = File('lib/features/mixer/mixer_desk_view.dart').readAsStringSync();
    final monitor = File('lib/features/monitor/compact_monitor_view.dart').readAsStringSync();
    final patchbay = File('lib/features/patchbay/patchbay_routing_modal.dart').readAsStringSync();

    test('mixer consumes shared tokens and operator controls', () {
      expect(mixer, contains("../../design/live_mix_tokens.dart"));
      expect(mixer, contains("../../design/widgets/lmm_controls.dart"));
      expect(mixer, contains('LmmToggleControl('));
      expect(mixer, contains('LmmFader('));
      expect(mixer, isNot(contains('const Color kSurfaceBase')));
      expect(mixer, isNot(contains('const Color kAccentOchre')));
    });

    test('field monitor consumes shared telemetry and fader controls', () {
      expect(monitor, contains("../../design/live_mix_tokens.dart"));
      expect(monitor, contains("../../design/widgets/lmm_controls.dart"));
      expect(monitor, contains('LmmStatusBadge('));
      expect(monitor, contains('LmmFader('));
      expect(monitor, isNot(contains('const Color kSurfaceBase')));
      expect(monitor, isNot(contains('const Color kMeterNominal')));
    });

    test('patchbay consumes repository-owned tokens instead of a private palette', () {
      expect(patchbay, contains("../../design/live_mix_tokens.dart"));
      expect(patchbay, contains('LiveMixTokens.accentOchre'));
      expect(patchbay, isNot(contains('static const _ochre')));
    });

    test('operator surfaces do not duplicate canonical token literals', () {
      const canonicalLiterals = <String>[
        '0xFF111315',
        '0xFF1C1F23',
        '0xFF24292F',
        '0xFFD96528',
        '0xFF2A7A6D',
        '0xFFD48822',
        '0xFF22C55E',
        '0xFFEAB308',
        '0xFFEF4444',
      ];

      for (final source in <String>[mixer, monitor, patchbay]) {
        for (final literal in canonicalLiterals) {
          expect(source, isNot(contains(literal)), reason: 'canonical color $literal must come from LiveMixTokens');
        }
      }
    });
  });
}
