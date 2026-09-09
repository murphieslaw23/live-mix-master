import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/design/component_state_registry.dart';
import 'package:live_mix_master/design/live_mix_tokens.dart';
import 'package:live_mix_master/design/widgets/lmm_state_widgets.dart';

void main() {
  group('component-states.json executable coverage', () {
    test('registry exactly preserves every required component state vocabulary', () {
      final source = jsonDecode(File('design/component-states.json').readAsStringSync()) as Map<String, dynamic>;
      final components = source['components'] as Map<String, dynamic>;

      expect(LiveMixComponentStateRegistry.statesByComponent.keys.toSet(), components.keys.toSet());
      for (final entry in components.entries) {
        final contract = entry.value as Map<String, dynamic>;
        final required = (contract['requiredStates'] as List<dynamic>).cast<String>().toSet();
        expect(
          LiveMixComponentStateRegistry.statesByComponent[entry.key],
          required,
          reason: '${entry.key} state vocabulary must match design/component-states.json',
        );
      }
    });

    testWidgets('record status covers idle live finalization success and write recovery states', (tester) async {
      for (final state in LmmRecordState.values) {
        await tester.pumpWidget(_host(LmmRecordStatus(state: state)));
        expect(find.text(LmmRecordStatus.copyFor(state)), findsOneWidget);
        final semantics = tester.getSemantics(find.byType(LmmRecordStatus));
        expect(semantics.label, contains('RECORD'));
        expect(semantics.value, contains(LmmRecordStatus.copyFor(state)));
      }
    });

    testWidgets('broadcast status covers preflight live reconnect and credential failure states', (tester) async {
      for (final state in LmmBroadcastState.values) {
        await tester.pumpWidget(_host(LmmBroadcastStatus(state: state)));
        expect(find.text(LmmBroadcastStatus.copyFor(state)), findsOneWidget);
        final semantics = tester.getSemantics(find.byType(LmmBroadcastStatus));
        expect(semantics.label, contains('BROADCAST'));
      }
      await tester.pumpWidget(_host(const LmmBroadcastStatus(state: LmmBroadcastState.invalidCredentials)));
      expect(find.byIcon(Icons.key_off_outlined), findsOneWidget);
    });

    testWidgets('fingerprint HUD retains provider timestamp identity fields and all lookup states', (tester) async {
      const timestamp = '2026-09-09T13:30:00Z';
      for (final state in LmmFingerprintState.values) {
        await tester.pumpWidget(_host(
          LmmFingerprintHud(
            state: state,
            artist: 'SYSTEM CORRUPT',
            title: 'TEKNO TOTEM',
            confidence: .91,
            provider: 'ACOUSTID',
            timestamp: timestamp,
          ),
        ));
        expect(find.text('SYSTEM CORRUPT'), findsOneWidget);
        expect(find.text('TEKNO TOTEM'), findsOneWidget);
        expect(find.textContaining('ACOUSTID'), findsWidgets);
        expect(find.textContaining(timestamp), findsOneWidget);
        expect(find.text(LmmFingerprintHud.copyFor(state)), findsOneWidget);
      }
    });

    testWidgets('session row preserves review state copy and action affordances', (tester) async {
      var approved = false;
      var ignored = false;
      var corrected = false;
      await tester.pumpWidget(_host(
        LmmSessionRow(
          state: LmmSessionRowState.needsReview,
          artist: 'ARTIST',
          title: 'TITLE',
          onApprove: () => approved = true,
          onIgnore: () => ignored = true,
          onCorrect: () => corrected = true,
        ),
      ));
      expect(find.text('NEEDS REVIEW'), findsOneWidget);
      expect(find.text('CORRECT'), findsOneWidget);
      expect(find.text('APPROVE'), findsOneWidget);
      expect(find.text('IGNORE'), findsOneWidget);
      await tester.tap(find.text('CORRECT'));
      await tester.tap(find.text('APPROVE'));
      await tester.tap(find.text('IGNORE'));
      expect(corrected, isTrue);
      expect(approved, isTrue);
      expect(ignored, isTrue);
    });

    testWidgets('channel critical states and trim control reinforce status without color alone', (tester) async {
      await tester.pumpWidget(_host(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LmmChannelStripStateBadge(label: 'USB LINE', state: LmmChannelStripState.disconnected),
            LmmChannelStripStateBadge(label: 'MASTER', state: LmmChannelStripState.clipping),
            LmmTrimKnob(label: 'TRIM', valueDb: 0, onChanged: null),
          ],
        ),
      ));
      expect(find.text('DISCONNECTED'), findsOneWidget);
      expect(find.text('CLIPPING'), findsOneWidget);
      expect(find.byIcon(Icons.link_off), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
      final size = tester.getSize(find.byType(LmmTrimKnob));
      expect(size.width, greaterThanOrEqualTo(LiveMixTokens.minimumTarget));
      expect(size.height, greaterThanOrEqualTo(LiveMixTokens.minimumTarget));
    });

    testWidgets('master bus exposes loudness true peak and limiter telemetry', (tester) async {
      await tester.pumpWidget(_host(
        const LmmMasterBusStatus(
          state: LmmMasterBusState.limiterOn,
          loudnessLufs: -14.2,
          truePeakDbtp: -0.2,
        ),
      ));
      expect(find.text('-14.2 LUFS'), findsOneWidget);
      expect(find.text('-0.2 dBTP'), findsOneWidget);
      expect(find.text('LIMITER ON'), findsOneWidget);
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
    });
  });
}

Widget _host(Widget child) => MaterialApp(
      theme: LiveMixTheme.dark(),
      home: Scaffold(body: Center(child: child)),
    );
