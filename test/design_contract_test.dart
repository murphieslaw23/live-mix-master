import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/design/live_mix_tokens.dart';

void main() {
  group('LiveMixMaster hybrid design token contract', () {
    late Map<String, dynamic> source;

    setUpAll(() async {
      source = jsonDecode(await File('design/tokens.json').readAsString()) as Map<String, dynamic>;
    });

    test('Dart colors exactly match design/tokens.json', () {
      final colors = source['colors'] as Map<String, dynamic>;

      expect(LiveMixTokens.surfaceBase, _color(colors['surface/base'] as String));
      expect(LiveMixTokens.surfaceRack, _color(colors['surface/rack'] as String));
      expect(LiveMixTokens.surfaceStrip, _color(colors['surface/strip'] as String));
      expect(LiveMixTokens.accentOchre, _color(colors['accent/ochre'] as String));
      expect(LiveMixTokens.accentCopper, _color(colors['accent/copper'] as String));
      expect(LiveMixTokens.statusWarn, _color(colors['status/warn'] as String));
      expect(LiveMixTokens.meterNominal, _color(colors['meter/nominal'] as String));
      expect(LiveMixTokens.meterHeadroom, _color(colors['meter/headroom'] as String));
      expect(LiveMixTokens.meterClip, _color(colors['meter/clip'] as String));
      expect(LiveMixTokens.meterInactive, _color(colors['meter/inactive'] as String));
      expect(LiveMixTokens.textPrimary, _color(colors['text/primary'] as String));
      expect(LiveMixTokens.textSecondary, _color(colors['text/secondary'] as String));
    });

    test('interaction, meter and focus constants match the repository contract', () {
      final interaction = source['interaction'] as Map<String, dynamic>;
      final focus = source['focus'] as Map<String, dynamic>;

      expect(LiveMixTokens.minimumTarget, interaction['minimumTargetPx']);
      expect(LiveMixTokens.focusWidth, focus['widthPx']);
      expect(LiveMixTokens.meterScaleDbfs, (source['meterScaleDbfs'] as List<dynamic>).cast<num>());
      expect(LiveMixTokens.spacing, (source['spacingPx'] as List<dynamic>).cast<num>());
      expect(LiveMixTokens.radii, (source['radiusPx'] as List<dynamic>).cast<num>());
    });

    test('theme exposes approved dark surfaces and semantic colors', () {
      final theme = LiveMixTheme.dark();

      expect(theme.scaffoldBackgroundColor, LiveMixTokens.surfaceBase);
      expect(theme.colorScheme.primary, LiveMixTokens.accentOchre);
      expect(theme.colorScheme.secondary, LiveMixTokens.accentCopper);
      expect(theme.colorScheme.surface, LiveMixTokens.surfaceRack);
      expect(theme.focusColor, LiveMixTokens.accentCopper);
    });

    test('typography roles use the approved families and metrics', () {
      expect(LiveMixTextStyles.sectionDisplay.fontFamily, 'Roboto Condensed');
      expect(LiveMixTextStyles.sectionDisplay.fontWeight, FontWeight.w700);
      expect(LiveMixTextStyles.uiLabel.fontFamily, 'Roboto Condensed');
      expect(LiveMixTextStyles.uiLabel.fontWeight, FontWeight.w600);
      expect(LiveMixTextStyles.body.fontFamily, 'Inter');
      expect(LiveMixTextStyles.numericTelemetry.fontFamily, 'Roboto Mono');
      expect(LiveMixTextStyles.numericTelemetry.fontWeight, FontWeight.w600);
    });
  });
}

Color _color(String hex) {
  final value = int.parse(hex.substring(1), radix: 16);
  return Color(0xFF000000 | value);
}
