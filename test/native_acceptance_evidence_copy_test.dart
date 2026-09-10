import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/native_acceptance_telemetry.dart';
import 'package:live_mix_master/features/mixer/native_acceptance_telemetry_panel.dart';

void main() {
  const snapshot = AcceptanceTelemetrySnapshot(
    captureState: null,
    sampleRate: 48000,
    bufferFrames: 256,
    inputChannels: 2,
    formatFlags: 0,
    callbackCount: 2400,
    xrunCount: 0,
    averageCallbackUs: 118.25,
    maxCallbackUs: 301.5,
    recorderQueueDepth: 1,
    fingerprintQueueDepth: 2,
    recorderRejectedBlocks: 0,
    fingerprintRejectedBlocks: 0,
  );

  test('snapshot exports deterministic non-secret Markdown evidence', () {
    final dynamic dynamicSnapshot = snapshot;
    final markdown = dynamicSnapshot.toEvidenceMarkdown() as String;

    expect(markdown, contains('## Same-process E2E telemetry'));
    expect(markdown, contains('- sample rate: 48000 Hz'));
    expect(markdown, contains('- buffer frames: 256'));
    expect(markdown, contains('- input channels: 2'));
    expect(markdown, contains('- callback count: 2400'));
    expect(markdown, contains('- average callback duration (us): 118.3'));
    expect(markdown, contains('- maximum callback duration (us): 301.5'));
    expect(markdown, contains('- xrun count: 0'));
    expect(markdown, contains('- recorder queue depth observed: 1'));
    expect(markdown, contains('- fingerprint queue depth observed: 2'));
    expect(markdown, contains('- recorder rejected blocks: 0'));
    expect(markdown, contains('- fingerprint rejected blocks: 0'));
    expect(markdown, contains('- queue overflow result: CLEAN'));

    final lower = markdown.toLowerCase();
    for (final forbidden in <String>[
      'uid',
      'token',
      'password',
      'authorization',
      '/users/',
      '/home/',
      'serial',
    ]) {
      expect(lower, isNot(contains(forbidden)));
    }
  });

  testWidgets('E2E telemetry panel copies the current snapshot evidence',
      (tester) async {
    String? copiedText;
    final messenger = TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<Object?, Object?>;
        copiedText = args['text'] as String?;
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NativeAcceptanceTelemetryPanel(
            telemetrySource: const _StaticTelemetrySource(snapshot),
            refreshInterval: const Duration(hours: 1),
          ),
        ),
      ),
    );

    expect(find.text('COPY EVIDENCE'), findsOneWidget);
    await tester.tap(find.text('COPY EVIDENCE'));
    await tester.pump();

    expect(copiedText, isNotNull);
    expect(copiedText, contains('## Same-process E2E telemetry'));
    expect(copiedText, contains('- callback count: 2400'));
    expect(copiedText, contains('- recorder rejected blocks: 0'));
    expect(copiedText, contains('- fingerprint rejected blocks: 0'));
  });
}

class _StaticTelemetrySource implements AcceptanceTelemetrySource {
  const _StaticTelemetrySource(this._snapshot);

  final AcceptanceTelemetrySnapshot _snapshot;

  @override
  AcceptanceTelemetrySnapshot get snapshot => _snapshot;
}
