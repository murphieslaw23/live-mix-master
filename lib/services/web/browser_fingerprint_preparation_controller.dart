import 'dart:async';

import 'browser_fingerprint_lookup_controller.dart';
import 'browser_fingerprint_preparation_gateway.dart';
import 'browser_fingerprint_preparation_runtime.dart';

enum BrowserFingerprintPreparationStatus {
  idle,
  collecting,
  preparing,
  prepared,
  tooShort,
  failed,
}

class BrowserFingerprintPreparationState {
  final BrowserFingerprintPreparationStatus status;
  final String message;
  final BrowserFingerprintPreparationFailure? failure;

  const BrowserFingerprintPreparationState({
    required this.status,
    required this.message,
    this.failure,
  });

  const BrowserFingerprintPreparationState.idle()
      : this(
          status: BrowserFingerprintPreparationStatus.idle,
          message: 'FINGERPRINT PREPARATION READY — AWAITING POST-MASTER AUDIO',
        );
}

typedef BrowserFingerprintPreparationListener = void Function(
  BrowserFingerprintPreparationState state,
);

class BrowserFingerprintPreparationController {
  BrowserFingerprintPreparationController({
    BrowserFingerprintPreparationGateway? gateway,
    required BrowserFingerprintLookupController lookupController,
  })  : _gateway = gateway ?? createBrowserFingerprintPreparationGateway(),
        _ownsGateway = gateway == null,
        _lookupController = lookupController;

  final BrowserFingerprintPreparationGateway _gateway;
  final bool _ownsGateway;
  final BrowserFingerprintLookupController _lookupController;
  final Set<BrowserFingerprintPreparationListener> _listeners = {};

  BrowserFingerprintPreparationState _state =
      const BrowserFingerprintPreparationState.idle();
  bool _busy = false;
  bool _disposed = false;

  BrowserFingerprintPreparationState get state => _state;
  bool get isBusy => _busy;

  void addListener(BrowserFingerprintPreparationListener listener) {
    _listeners.add(listener);
  }

  void removeListener(BrowserFingerprintPreparationListener listener) {
    _listeners.remove(listener);
  }

  Future<void> prepareAndLookup({
    required List<double> interleavedSamples,
    required int sampleRate,
    int channels = 2,
  }) async {
    if (_disposed) {
      _setFailure(BrowserFingerprintPreparationFailure.disposed);
      return;
    }
    if (_busy) {
      _setFailure(BrowserFingerprintPreparationFailure.busy);
      return;
    }

    _busy = true;
    _setState(
      const BrowserFingerprintPreparationState(
        status: BrowserFingerprintPreparationStatus.collecting,
        message: 'FINGERPRINT AUDIO WINDOW COLLECTED — PREPARATION PENDING',
      ),
    );
    _setState(
      const BrowserFingerprintPreparationState(
        status: BrowserFingerprintPreparationStatus.preparing,
        message: 'FINGERPRINT PREPARATION IN PROGRESS — MIX / RECORDING CONTINUE',
      ),
    );

    try {
      final result = await _gateway.prepare(
        interleavedSamples: interleavedSamples,
        sampleRate: sampleRate,
        channels: channels,
      );
      if (_disposed) return;

      _setState(
        const BrowserFingerprintPreparationState(
          status: BrowserFingerprintPreparationStatus.prepared,
          message: 'FINGERPRINT PREPARED — PROVIDER LOOKUP CONTINUES SERVER-SIDE',
        ),
      );
      await _lookupController.lookupPreparedFingerprint(
        fingerprint: result.fingerprint,
        durationSeconds: result.durationSeconds,
      );
    } on BrowserFingerprintPreparationException catch (error) {
      if (_disposed) return;
      if (error.failure == BrowserFingerprintPreparationFailure.tooShort) {
        _setState(
          const BrowserFingerprintPreparationState(
            status: BrowserFingerprintPreparationStatus.tooShort,
            failure: BrowserFingerprintPreparationFailure.tooShort,
            message: 'FINGERPRINT AUDIO WINDOW TOO SHORT — SESSION CONTINUES',
          ),
        );
      } else {
        _setFailure(error.failure);
      }
    } on TimeoutException {
      if (!_disposed) {
        _setFailure(BrowserFingerprintPreparationFailure.timeout);
      }
    } catch (_) {
      if (!_disposed) {
        _setFailure(BrowserFingerprintPreparationFailure.unavailable);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _busy = false;
    _listeners.clear();
    if (_ownsGateway) {
      await _gateway.dispose();
    }
  }

  void _setFailure(BrowserFingerprintPreparationFailure failure) {
    _setState(
      BrowserFingerprintPreparationState(
        status: BrowserFingerprintPreparationStatus.failed,
        failure: failure,
        message: _failureMessage(failure),
      ),
    );
  }

  void _setState(BrowserFingerprintPreparationState state) {
    _state = state;
    for (final listener in List<BrowserFingerprintPreparationListener>.of(_listeners)) {
      listener(state);
    }
  }

  static String _failureMessage(BrowserFingerprintPreparationFailure failure) {
    switch (failure) {
      case BrowserFingerprintPreparationFailure.tooShort:
        return 'FINGERPRINT AUDIO WINDOW TOO SHORT — SESSION CONTINUES';
      case BrowserFingerprintPreparationFailure.timeout:
        return 'FINGERPRINT PREPARATION TIMEOUT — MIX / RECORDING CONTINUE';
      case BrowserFingerprintPreparationFailure.busy:
        return 'FINGERPRINT PREPARATION BUSY — SESSION CONTINUES';
      case BrowserFingerprintPreparationFailure.unsupported:
        return 'FINGERPRINT PREPARATION UNSUPPORTED — MIX / RECORDING CONTINUE';
      case BrowserFingerprintPreparationFailure.invalidAudio:
      case BrowserFingerprintPreparationFailure.unavailable:
      case BrowserFingerprintPreparationFailure.disposed:
        return 'FINGERPRINT PREPARATION UNAVAILABLE — MIX / RECORDING CONTINUE';
    }
  }
}
