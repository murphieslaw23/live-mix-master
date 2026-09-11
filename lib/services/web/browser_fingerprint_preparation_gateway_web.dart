import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'browser_fingerprint_preparation_gateway.dart';

const String _workerPath = 'fingerprint/livemixmaster-fingerprint-worker.js';
const String _modulePath = '/fingerprint/vendor/livemixmaster-chromaprint.mjs';
const String _wasmPath = '/fingerprint/vendor/livemixmaster-chromaprint-core.wasm';
const Duration _startupTimeout = Duration(seconds: 4);
const Duration _preparationTimeout = Duration(seconds: 8);

BrowserFingerprintPreparationGateway createBrowserFingerprintPreparationGateway() {
  return WebBrowserFingerprintPreparationGateway();
}

class WebBrowserFingerprintPreparationGateway
    implements BrowserFingerprintPreparationGateway {
  web.Worker? _worker;
  Completer<void>? _readyCompleter;
  Completer<PreparedBrowserFingerprint>? _activeCompleter;
  int? _activeRequestId;
  int _nextRequestId = 1;
  bool _disposed = false;

  @override
  Future<PreparedBrowserFingerprint> prepare({
    required List<double> interleavedSamples,
    required int sampleRate,
    int channels = 2,
  }) async {
    if (_disposed) {
      throw const BrowserFingerprintPreparationException(
        BrowserFingerprintPreparationFailure.disposed,
        'FINGERPRINT PREPARATION UNAVAILABLE',
      );
    }
    if (_activeCompleter != null) {
      throw const BrowserFingerprintPreparationException(
        BrowserFingerprintPreparationFailure.busy,
        'FINGERPRINT PREPARATION BUSY',
      );
    }
    if (
        sampleRate <= 0 ||
        (channels != 1 && channels != 2) ||
        interleavedSamples.isEmpty ||
        interleavedSamples.length % channels != 0) {
      throw const BrowserFingerprintPreparationException(
        BrowserFingerprintPreparationFailure.invalidAudio,
        'FINGERPRINT AUDIO WINDOW INVALID',
      );
    }

    await _ensureReady();
    final worker = _worker;
    if (worker == null || _disposed) {
      throw const BrowserFingerprintPreparationException(
        BrowserFingerprintPreparationFailure.unavailable,
        'FINGERPRINT PREPARATION UNAVAILABLE',
      );
    }

    final pcmRequestId = _nextRequestId++;
    final flushRequestId = _nextRequestId++;
    final completer = Completer<PreparedBrowserFingerprint>();
    _activeCompleter = completer;
    _activeRequestId = flushRequestId;

    final samples = Float32List.fromList(interleavedSamples).toJS;
    worker.postMessage(
      <String, Object?>{
        'type': 'pcm',
        'requestId': pcmRequestId,
        'samples': samples,
        'frames': interleavedSamples.length ~/ channels,
        'sampleRate': sampleRate,
        'channels': channels,
      }.jsify(),
    );
    worker.postMessage(
      <String, Object?>{
        'type': 'flush',
        'requestId': flushRequestId,
      }.jsify(),
    );

    try {
      return await completer.future.timeout(_preparationTimeout);
    } on TimeoutException {
      throw const BrowserFingerprintPreparationException(
        BrowserFingerprintPreparationFailure.timeout,
        'FINGERPRINT PREPARATION TIMEOUT',
      );
    } finally {
      if (identical(_activeCompleter, completer)) {
        _activeCompleter = null;
        _activeRequestId = null;
      }
    }
  }

  Future<void> _ensureReady() async {
    if (_disposed) {
      throw const BrowserFingerprintPreparationException(
        BrowserFingerprintPreparationFailure.disposed,
        'FINGERPRINT PREPARATION UNAVAILABLE',
      );
    }
    final existing = _readyCompleter;
    if (existing != null) {
      try {
        await existing.future.timeout(_startupTimeout);
        return;
      } on TimeoutException {
        throw const BrowserFingerprintPreparationException(
          BrowserFingerprintPreparationFailure.timeout,
          'FINGERPRINT PREPARATION STARTUP TIMEOUT',
        );
      }
    }

    final worker = web.Worker(
      _workerPath.toJS,
      web.WorkerOptions(type: 'module'),
    );
    final ready = Completer<void>();
    _worker = worker;
    _readyCompleter = ready;

    worker.addEventListener(
      'message',
      ((web.Event event) => _handleMessage(event)).toJS,
    );
    worker.addEventListener(
      'error',
      ((web.Event _) => _handleWorkerFailure()).toJS,
    );
    worker.postMessage(
      <String, Object?>{
        'type': 'init',
        'moduleUrl': _modulePath,
        'wasmUrl': _wasmPath,
      }.jsify(),
    );

    try {
      await ready.future.timeout(_startupTimeout);
    } on TimeoutException {
      worker.terminate();
      if (identical(_worker, worker)) {
        _worker = null;
        _readyCompleter = null;
      }
      throw const BrowserFingerprintPreparationException(
        BrowserFingerprintPreparationFailure.timeout,
        'FINGERPRINT PREPARATION STARTUP TIMEOUT',
      );
    }
  }

  void _handleMessage(web.Event event) {
    final message = (event as JSObject)['data'];
    switch (_messageString(message, 'type')) {
      case 'ready':
        final ready = _readyCompleter;
        if (ready != null && !ready.isCompleted) {
          ready.complete();
        }
        return;
      case 'fingerprint':
        final requestId = _messageInt(message, 'requestId');
        final completer = _activeCompleter;
        if (requestId != _activeRequestId || completer == null || completer.isCompleted) {
          return;
        }
        final fingerprint = _messageString(message, 'fingerprint');
        final durationSeconds = _messageInt(message, 'durationSeconds');
        if (fingerprint == null || fingerprint.isEmpty || durationSeconds <= 0) {
          completer.completeError(
            const BrowserFingerprintPreparationException(
              BrowserFingerprintPreparationFailure.unavailable,
              'FINGERPRINT PREPARATION UNAVAILABLE',
            ),
          );
          return;
        }
        completer.complete(
          PreparedBrowserFingerprint(
            fingerprint: fingerprint,
            durationSeconds: durationSeconds,
          ),
        );
        return;
      case 'fingerprintError':
        final requestId = _messageInt(message, 'requestId');
        final failure = _workerFailure(_messageString(message, 'failureCode'));
        final ready = _readyCompleter;
        if (_activeCompleter == null && ready != null && !ready.isCompleted) {
          ready.completeError(
            BrowserFingerprintPreparationException(
              failure,
              'FINGERPRINT PREPARATION UNAVAILABLE',
            ),
          );
          return;
        }
        final completer = _activeCompleter;
        if (requestId == _activeRequestId && completer != null && !completer.isCompleted) {
          completer.completeError(
            BrowserFingerprintPreparationException(
              failure,
              'FINGERPRINT PREPARATION FAILED',
            ),
          );
        }
        return;
      case 'pcmAck':
      default:
        return;
    }
  }

  void _handleWorkerFailure() {
    final failure = const BrowserFingerprintPreparationException(
      BrowserFingerprintPreparationFailure.unavailable,
      'FINGERPRINT PREPARATION UNAVAILABLE',
    );
    final ready = _readyCompleter;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(failure);
    }
    final active = _activeCompleter;
    if (active != null && !active.isCompleted) {
      active.completeError(failure);
    }
  }

  BrowserFingerprintPreparationFailure _workerFailure(String? code) {
    switch (code) {
      case 'tooShort':
        return BrowserFingerprintPreparationFailure.tooShort;
      case 'busy':
        return BrowserFingerprintPreparationFailure.busy;
      case 'invalidAudio':
        return BrowserFingerprintPreparationFailure.invalidAudio;
      case 'disposed':
        return BrowserFingerprintPreparationFailure.disposed;
      case 'versionMismatch':
      case 'notReady':
      case 'invalidRequest':
      case 'unavailable':
      default:
        return BrowserFingerprintPreparationFailure.unavailable;
    }
  }

  String? _messageString(JSAny? message, String key) {
    if (message == null) return null;
    try {
      return (message as JSObject)[key]?.dartify()?.toString();
    } on Object {
      return null;
    }
  }

  int _messageInt(JSAny? message, String key) {
    if (message == null) return 0;
    try {
      final value = (message as JSObject)[key]?.dartify();
      return value is num ? value.toInt() : 0;
    } on Object {
      return 0;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final active = _activeCompleter;
    if (active != null && !active.isCompleted) {
      active.completeError(
        const BrowserFingerprintPreparationException(
          BrowserFingerprintPreparationFailure.disposed,
          'FINGERPRINT PREPARATION UNAVAILABLE',
        ),
      );
    }
    final worker = _worker;
    if (worker != null) {
      worker.postMessage(<String, Object?>{'type': 'dispose'}.jsify());
      worker.terminate();
    }
    _worker = null;
    _readyCompleter = null;
    _activeCompleter = null;
    _activeRequestId = null;
  }
}
