import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/services/web/browser_fingerprint_lookup_controller.dart';
import 'package:live_mix_master/services/web/browser_fingerprint_preparation_controller.dart';
import 'package:live_mix_master/services/web/browser_fingerprint_preparation_gateway.dart';
import 'package:live_mix_master/services/web/fingerprint_proxy_client.dart';

void main() {
  group('BrowserFingerprintPreparationController', () {
    test('prepares bounded PCM and forwards only fingerprint + duration to lookup', () async {
      final preparationGateway = _PreparationGateway(
        const PreparedBrowserFingerprint(
          fingerprint: 'chromaprint-fixture',
          durationSeconds: 10,
        ),
      );
      final lookupGateway = _LookupGateway();
      final lookupController = BrowserFingerprintLookupController(gateway: lookupGateway);
      final controller = BrowserFingerprintPreparationController(
        gateway: preparationGateway,
        lookupController: lookupController,
      );
      final statuses = <BrowserFingerprintPreparationStatus>[];
      controller.addListener((state) => statuses.add(state.status));

      await controller.prepareAndLookup(
        interleavedSamples: List<double>.filled(960000, 0.125),
        sampleRate: 48000,
        channels: 2,
      );

      expect(preparationGateway.prepareCalls, 1);
      expect(preparationGateway.lastSampleRate, 48000);
      expect(preparationGateway.lastChannels, 2);
      expect(preparationGateway.lastSampleCount, 960000);
      expect(lookupGateway.fingerprints, ['chromaprint-fixture']);
      expect(lookupGateway.durations, [10]);
      expect(statuses, [
        BrowserFingerprintPreparationStatus.collecting,
        BrowserFingerprintPreparationStatus.preparing,
        BrowserFingerprintPreparationStatus.prepared,
      ]);
      expect(controller.state.status, BrowserFingerprintPreparationStatus.prepared);
      expect(
        controller.state.message,
        'FINGERPRINT PREPARED — PROVIDER LOOKUP CONTINUES SERVER-SIDE',
      );
    });

    test('maps short audio to fixed too-short state without provider lookup', () async {
      final preparationGateway = _PreparationGateway.failure(
        const BrowserFingerprintPreparationException(
          BrowserFingerprintPreparationFailure.tooShort,
          'raw worker detail must not escape',
        ),
      );
      final lookupGateway = _LookupGateway();
      final controller = BrowserFingerprintPreparationController(
        gateway: preparationGateway,
        lookupController: BrowserFingerprintLookupController(gateway: lookupGateway),
      );

      await controller.prepareAndLookup(
        interleavedSamples: List<double>.filled(48000, 0),
        sampleRate: 48000,
        channels: 2,
      );

      expect(controller.state.status, BrowserFingerprintPreparationStatus.tooShort);
      expect(
        controller.state.message,
        'FINGERPRINT AUDIO WINDOW TOO SHORT — SESSION CONTINUES',
      );
      expect(controller.state.message, isNot(contains('raw worker detail')));
      expect(lookupGateway.fingerprints, isEmpty);
    });

    test('maps timeout/unavailable failures to deterministic non-secret copy', () async {
      for (final fixture in [
        (
          BrowserFingerprintPreparationFailure.timeout,
          'FINGERPRINT PREPARATION TIMEOUT — MIX / RECORDING CONTINUE',
        ),
        (
          BrowserFingerprintPreparationFailure.unavailable,
          'FINGERPRINT PREPARATION UNAVAILABLE — MIX / RECORDING CONTINUE',
        ),
      ]) {
        final controller = BrowserFingerprintPreparationController(
          gateway: _PreparationGateway.failure(
            BrowserFingerprintPreparationException(fixture.$1, 'secret-ish internal detail'),
          ),
          lookupController: BrowserFingerprintLookupController(gateway: _LookupGateway()),
        );

        await controller.prepareAndLookup(
          interleavedSamples: List<double>.filled(960000, 0),
          sampleRate: 48000,
          channels: 2,
        );

        expect(controller.state.status, BrowserFingerprintPreparationStatus.failed);
        expect(controller.state.failure, fixture.$1);
        expect(controller.state.message, fixture.$2);
        expect(controller.state.message, isNot(contains('secret-ish')));
      }
    });

    test('does not overlap preparation calls', () async {
      final completer = Completer<PreparedBrowserFingerprint>();
      final preparationGateway = _PreparationGateway.pending(completer.future);
      final lookupGateway = _LookupGateway();
      final controller = BrowserFingerprintPreparationController(
        gateway: preparationGateway,
        lookupController: BrowserFingerprintLookupController(gateway: lookupGateway),
      );
      final samples = List<double>.filled(960000, 0);

      final first = controller.prepareAndLookup(
        interleavedSamples: samples,
        sampleRate: 48000,
        channels: 2,
      );
      await Future<void>.delayed(Duration.zero);
      await controller.prepareAndLookup(
        interleavedSamples: samples,
        sampleRate: 48000,
        channels: 2,
      );

      expect(preparationGateway.prepareCalls, 1);
      expect(controller.state.status, BrowserFingerprintPreparationStatus.failed);
      expect(controller.state.failure, BrowserFingerprintPreparationFailure.busy);

      completer.complete(
        const PreparedBrowserFingerprint(
          fingerprint: 'completed-first',
          durationSeconds: 10,
        ),
      );
      await first;
      expect(lookupGateway.fingerprints, ['completed-first']);
    });
  });
}

class _PreparationGateway implements BrowserFingerprintPreparationGateway {
  _PreparationGateway(this.result) : error = null, pending = null;
  _PreparationGateway.failure(this.error) : result = null, pending = null;
  _PreparationGateway.pending(this.pending) : result = null, error = null;

  final PreparedBrowserFingerprint? result;
  final BrowserFingerprintPreparationException? error;
  final Future<PreparedBrowserFingerprint>? pending;
  int prepareCalls = 0;
  int? lastSampleRate;
  int? lastChannels;
  int? lastSampleCount;

  @override
  Future<PreparedBrowserFingerprint> prepare({
    required List<double> interleavedSamples,
    required int sampleRate,
    int channels = 2,
  }) async {
    prepareCalls += 1;
    lastSampleRate = sampleRate;
    lastChannels = channels;
    lastSampleCount = interleavedSamples.length;
    if (error != null) throw error!;
    if (pending != null) return pending!;
    return result!;
  }

  @override
  Future<void> dispose() async {}
}

class _LookupGateway implements BrowserFingerprintLookupGateway {
  final fingerprints = <String>[];
  final durations = <int>[];

  @override
  Future<FingerprintProxyResult> lookup({
    required String fingerprint,
    required int durationSeconds,
    double minimumConfidence = 0.65,
  }) async {
    fingerprints.add(fingerprint);
    durations.add(durationSeconds);
    return const FingerprintProxyResult.noMatch();
  }
}
