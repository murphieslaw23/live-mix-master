import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

const String _workerPath = 'fingerprint/livemixmaster-fingerprint-worker.js';
const String _modulePath = '/fingerprint/vendor/livemixmaster-chromaprint.mjs';
const String _wasmPath = '/fingerprint/vendor/livemixmaster-chromaprint-core.wasm';
const int maximumOutstandingPcm = 4;
const int initialWindowSeconds = 10;
const int analysisCadenceSeconds = 8;
const Duration _startupTimeout = Duration(seconds: 4);

typedef BrowserPreparedFingerprintHandler = Future<void> Function({
  required String fingerprint,
  required int durationSeconds,
});

typedef BrowserFingerprintAnalysisReadyHandler = void Function(
  int maximumOutstandingPcm,
);
typedef BrowserFingerprintAnalysisAckHandler = void Function();
typedef BrowserFingerprintAnalysisUnavailableHandler = void Function();

class WebBrowserFingerprintAnalysisBridge {
  WebBrowserFingerprintAnalysisBridge({
    required this.preparedFingerprintHandler,
    required this.onReady,
    required this.onAnalysisAck,
    required this.onUnavailable,
  });

  final BrowserPreparedFingerprintHandler preparedFingerprintHandler;
  final BrowserFingerprintAnalysisReadyHandler onReady;
  final BrowserFingerprintAnalysisAckHandler onAnalysisAck;
  final BrowserFingerprintAnalysisUnavailableHandler onUnavailable;

  web.Worker? _worker;
  Completer<void>? _readyCompleter;
  final Set<int> _pcmRequestIds = <int>{};
  int _nextRequestId = 1;
  int _acceptedFrames = 0;
  int _nextFlushFrame = 0;
  int _sampleRate = 0;
  int? _activeFlushRequestId;
  bool _flushInFlight = false;
  bool _ready = false;
  bool _disposed = false;

  int get acceptedFrames => _acceptedFrames;
  int get nextFlushFrame => _nextFlushFrame;

  Future<void> start() async {
    if (_disposed || _worker != null) return;

    final worker = web.Worker(
      _workerPath.toJS,
      web.WorkerOptions(type: 'module'),
    );
    final ready = Completer<void>();
    _worker = worker;
    _readyCompleter = ready;

    worker.addEventListener(
      'message',
      ((web.Event event) => _handleWorkerMessage(event)).toJS,
    );
    worker.addEventListener(
      'error',
      ((web.Event _) => _failClosed()).toJS,
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
    } on Object {
      _failClosed();
    }
  }

  void forwardAnalysisPcm(JSAny? message) {
    final worker = _worker;
    if (_disposed || !_ready || worker == null || message == null) {
      return;
    }

    final frames = _messageInt(message, 'frames');
    final sampleRate = _messageInt(message, 'sampleRate');
    final channels = _messageInt(message, 'channels');
    final samples = (message as JSObject)['samples'];
    if (
        frames <= 0 ||
        sampleRate <= 0 ||
        channels != 2 ||
        samples == null) {
      onAnalysisAck();
      return;
    }

    final requestId = _nextRequestId++;
    _sampleRate = sampleRate;
    _pcmRequestIds.add(requestId);
    final forwarded = message as JSObject;
    forwarded['type'] = 'pcm'.toJS;
    forwarded['requestId'] = requestId.toJS;
    worker.postMessage(forwarded);
  }

  void _handleWorkerMessage(web.Event event) {
    if (_disposed) return;
    final message = (event as JSObject)['data'];
    switch (_messageString(message, 'type')) {
      case 'ready':
        _ready = true;
        _acceptedFrames = 0;
        _nextFlushFrame = 0;
        _sampleRate = 0;
        final ready = _readyCompleter;
        if (ready != null && !ready.isCompleted) {
          ready.complete();
        }
        onReady(maximumOutstandingPcm);
        return;
      case 'pcmAck':
        final requestId = _messageInt(message, 'requestId');
        if (!_pcmRequestIds.remove(requestId)) return;
        _acceptedFrames += _messageInt(message, 'frames');
        onAnalysisAck();
        _maybeFlush();
        return;
      case 'fingerprint':
        final requestId = _messageInt(message, 'requestId');
        if (requestId != _activeFlushRequestId) return;
        final fingerprint = _messageString(message, 'fingerprint');
        final durationSeconds = _messageInt(message, 'durationSeconds');
        _completeFlushCadence();
        if (fingerprint == null || fingerprint.isEmpty || durationSeconds <= 0) {
          return;
        }
        unawaited(
          preparedFingerprintHandler(
            fingerprint: fingerprint,
            durationSeconds: durationSeconds,
          ).catchError((_) {}),
        );
        return;
      case 'fingerprintError':
        final requestId = _messageInt(message, 'requestId');
        if (_pcmRequestIds.remove(requestId)) {
          onAnalysisAck();
          return;
        }
        if (requestId == _activeFlushRequestId) {
          _completeFlushCadence();
        }
        return;
      default:
        return;
    }
  }

  void _maybeFlush() {
    final worker = _worker;
    if (
        worker == null ||
        !_ready ||
        _disposed ||
        _flushInFlight ||
        _sampleRate <= 0) {
      return;
    }

    if (_nextFlushFrame == 0) {
      _nextFlushFrame = _sampleRate * initialWindowSeconds;
    }
    if (_acceptedFrames < _nextFlushFrame) return;

    final requestId = _nextRequestId++;
    _activeFlushRequestId = requestId;
    _flushInFlight = true;
    worker.postMessage(
      <String, Object?>{
        'type': 'flush',
        'requestId': requestId,
      }.jsify(),
    );
  }

  void _completeFlushCadence() {
    _flushInFlight = false;
    _activeFlushRequestId = null;
    if (_sampleRate > 0) {
      _nextFlushFrame = _acceptedFrames + (_sampleRate * analysisCadenceSeconds);
    }
  }

  void _failClosed() {
    if (_disposed) return;
    _ready = false;
    _flushInFlight = false;
    _activeFlushRequestId = null;
    final pendingPcm = _pcmRequestIds.length;
    _pcmRequestIds.clear();
    for (var index = 0; index < pendingPcm; index += 1) {
      onAnalysisAck();
    }
    final ready = _readyCompleter;
    if (ready != null && !ready.isCompleted) {
      ready.complete();
    }
    onUnavailable();
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

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _ready = false;
    _flushInFlight = false;
    _activeFlushRequestId = null;
    _pcmRequestIds.clear();
    final worker = _worker;
    if (worker != null) {
      worker.postMessage(<String, Object?>{'type': 'dispose'}.jsify());
      worker.terminate();
    }
    _worker = null;
    _readyCompleter = null;
  }
}
