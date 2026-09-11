import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'browser_audio_processing_controller.dart';
import 'browser_capture_controller.dart';
import 'browser_mixer_controller.dart';
import 'browser_mixer_protocol.dart';
import 'browser_recording_controller.dart';

typedef BrowserActiveStreamProvider = web.MediaStream? Function();

const int _recorderMaxBytes = 64 * 1024 * 1024;
const int _recorderRenderQuantumFrames = 128;
const int _recorderBackpressureBudgetMilliseconds = 500;
const Duration _recorderHandshakeTimeout = Duration(seconds: 2);
const Duration _recorderStopTimeout = Duration(seconds: 2);
const Duration _recorderExportTimeout = Duration(seconds: 2);

class WebAudioWorkletGateway
    implements
        BrowserAudioProcessingGateway,
        BrowserMixerGateway,
        BrowserRecordingGateway,
        BrowserRecordingLifecycleGateway {
  WebAudioWorkletGateway({required BrowserActiveStreamProvider activeStream})
      : _activeStream = activeStream;

  final BrowserActiveStreamProvider _activeStream;
  final StreamController<BrowserMixerTelemetry> _mixerTelemetry =
      StreamController<BrowserMixerTelemetry>.broadcast();

  web.AudioContext? _context;
  web.MediaStreamAudioSourceNode? _sourceNode;
  web.AudioWorkletNode? _workletNode;
  web.MediaStreamAudioDestinationNode? _destinationNode;
  web.Worker? _recorderWorker;

  Completer<void>? _recorderStartCompleter;
  Completer<BrowserRecordingArtifact>? _recorderStopCompleter;
  Completer<web.Blob>? _recorderExportCompleter;
  BrowserRecordingArtifact? _lastRecordingArtifact;
  void Function(BrowserRecordingException failure)? _recordingFailureHandler;
  bool _recordingActive = false;

  @override
  Stream<BrowserMixerTelemetry> get telemetry => _mixerTelemetry.stream;

  @override
  Future<void> configure(BrowserMixerConfiguration configuration) async {
    final workletNode = _workletNode;
    if (workletNode == null) {
      throw StateError(
        'MIXER CONFIGURATION UNAVAILABLE — AUDIOWORKLET NOT ACTIVE',
      );
    }
    workletNode.port.postMessage(configuration.toMessage().jsify());
  }

  @override
  void setRecordingFailureHandler(
    void Function(BrowserRecordingException failure) handler,
  ) {
    _recordingFailureHandler = handler;
  }

  @override
  Future<BrowserAudioProcessingAttempt> start(BrowserCaptureSource source) async {
    await stop();

    if (!web.window.isSecureContext) {
      return const BrowserAudioProcessingAttempt.unsupported(
        'AUDIOWORKLET NOT AVAILABLE — SECURE BROWSER CONTEXT REQUIRED',
      );
    }

    final stream = _activeStream();
    if (stream == null || stream.getAudioTracks().toDart.isEmpty) {
      return const BrowserAudioProcessingAttempt.failed(
        'AUDIOWORKLET START FAILED — ACTIVE CAPTURE STREAM UNAVAILABLE',
      );
    }

    final context = web.AudioContext();
    web.Worker? startedRecorderWorker;
    try {
      await context.audioWorklet.addModule('audio/livemixmaster-worklet.js').toDart;

      final sourceNode = context.createMediaStreamSource(stream);
      final workletNode = web.AudioWorkletNode(context, 'livemixmaster-dsp');
      final destinationNode = context.createMediaStreamDestination();
      final recorderWorker = web.Worker(
        'audio/livemixmaster-recorder-worker.js'.toJS,
        web.WorkerOptions(type: 'module'),
      );
      startedRecorderWorker = recorderWorker;

      workletNode.port.addEventListener(
        'message',
        ((web.Event event) {
          final message = (event as JSObject)['data'];
          switch (_messageType(message)) {
            case 'pcm':
              recorderWorker.postMessage(message);
              break;
            case 'telemetry':
              final telemetry =
                  BrowserMixerTelemetry.tryParse(message?.dartify());
              if (telemetry != null && !_mixerTelemetry.isClosed) {
                _mixerTelemetry.add(telemetry);
              }
              workletNode.port.postMessage(
                <String, Object?>{'type': 'telemetryAck'}.jsify(),
              );
              break;
            case 'recordingError':
              final failure = const BrowserRecordingException(
                BrowserRecordingFailure.backpressure,
                'RECORDING FAILED — AUDIO BACKPRESSURE',
              );
              _setWorkletRecording(workletNode, enabled: false);
              recorderWorker.postMessage(
                <String, Object?>{'type': 'stop'}.jsify(),
              );
              _recordingActive = false;
              _failPendingRecordingOperations(failure);
              _notifyRecordingFailure(failure);
              break;
            default:
              break;
          }
        }).toJS,
      );
      workletNode.port.start();

      recorderWorker.addEventListener(
        'message',
        ((web.Event event) {
          final message = (event as JSObject)['data'];
          switch (_messageType(message)) {
            case 'pcmAck':
              workletNode.port.postMessage(message);
              break;
            case 'recordingStarted':
              final completer = _recorderStartCompleter;
              if (completer != null && !completer.isCompleted) {
                completer.complete();
              }
              break;
            case 'recordingStopped':
              final artifact = BrowserRecordingArtifact(
                fileName: _messageString(message, 'fileName') ?? 'livemixmaster.wav',
                bytesWritten: _messageInt(message, 'bytesWritten'),
                dataBytes: _messageInt(message, 'dataBytes'),
              );
              _lastRecordingArtifact = artifact;
              _recordingActive = false;
              final completer = _recorderStopCompleter;
              if (completer != null && !completer.isCompleted) {
                completer.complete(artifact);
              }
              break;
            case 'recordingExport':
              final blob = _messageBlob(message, 'file');
              final completer = _recorderExportCompleter;
              if (blob != null && completer != null && !completer.isCompleted) {
                completer.complete(blob);
              } else if (completer != null && !completer.isCompleted) {
                final failure = const BrowserRecordingException(
                  BrowserRecordingFailure.exportFailed,
                  'WAV EXPORT FAILED — FINALIZED RECORDING UNAVAILABLE',
                );
                completer.completeError(failure);
                _notifyRecordingFailure(failure);
              }
              break;
            case 'recordingError':
              _setWorkletRecording(workletNode, enabled: false);
              _recordingActive = false;
              final failure = _workerRecordingFailure(message);
              _failPendingRecordingOperations(failure);
              _notifyRecordingFailure(failure);
              break;
            default:
              break;
          }
        }).toJS,
      );

      sourceNode.connect(workletNode);
      workletNode.connect(destinationNode);
      await context.resume().toDart;

      _context = context;
      _sourceNode = sourceNode;
      _workletNode = workletNode;
      _destinationNode = destinationNode;
      _recorderWorker = recorderWorker;
      _lastRecordingArtifact = null;
      _recordingActive = false;

      return const BrowserAudioProcessingAttempt.started();
    } on Object catch (error) {
      startedRecorderWorker?.terminate();
      try {
        await context.close().toDart;
      } on Object {
        // Preserve the original startup failure.
      }
      return BrowserAudioProcessingAttempt.failed(
        'AUDIOWORKLET START FAILED — ${_sanitize(error)}',
      );
    }
  }

  @override
  Future<void> startRecording() async {
    final context = _context;
    final workletNode = _workletNode;
    final recorderWorker = _recorderWorker;
    if (context == null || workletNode == null || recorderWorker == null) {
      throw const BrowserRecordingException(
        BrowserRecordingFailure.notReady,
        'RECORDING UNAVAILABLE — AUDIOWORKLET NOT ACTIVE',
      );
    }
    if (_recordingActive || _recorderStartCompleter != null) {
      throw const BrowserRecordingException(
        BrowserRecordingFailure.notReady,
        'RECORDING UNAVAILABLE — RECORDING ALREADY ACTIVE',
      );
    }

    _lastRecordingArtifact = null;
    final startCompleter = Completer<void>();
    _recorderStartCompleter = startCompleter;
    recorderWorker.postMessage(
      <String, Object?>{
        'type': 'start',
        'sampleRate': context.sampleRate.round(),
        'channels': 2,
        'sampleFormat': 'pcm24',
        'maxBytes': _recorderMaxBytes,
      }.jsify(),
    );

    try {
      await _recorderStartCompleter!.future.timeout(_recorderHandshakeTimeout);
    } on TimeoutException {
      recorderWorker.postMessage(
        <String, Object?>{'type': 'stop'}.jsify(),
      );
      throw const BrowserRecordingException(
        BrowserRecordingFailure.writeFailed,
        'RECORDING FAILED — RECORDER WORKER START TIMEOUT',
      );
    } finally {
      if (identical(_recorderStartCompleter, startCompleter)) {
        _recorderStartCompleter = null;
      }
    }

    _setWorkletRecording(
      workletNode,
      enabled: true,
      maxOutstandingPcm: _recorderMaxOutstandingPcm(context.sampleRate),
    );
    _recordingActive = true;
  }

  @override
  Future<BrowserRecordingArtifact> stopRecording() async {
    final workletNode = _workletNode;
    final recorderWorker = _recorderWorker;
    if (!_recordingActive || workletNode == null || recorderWorker == null) {
      throw const BrowserRecordingException(
        BrowserRecordingFailure.notReady,
        'RECORDING STOP FAILED — RECORDING NOT ACTIVE',
      );
    }

    _setWorkletRecording(workletNode, enabled: false);
    _recordingActive = false;

    final stopCompleter = Completer<BrowserRecordingArtifact>();
    _recorderStopCompleter = stopCompleter;
    recorderWorker.postMessage(
      <String, Object?>{'type': 'stop'}.jsify(),
    );

    try {
      return await _recorderStopCompleter!.future.timeout(_recorderStopTimeout);
    } on TimeoutException {
      throw const BrowserRecordingException(
        BrowserRecordingFailure.writeFailed,
        'RECORDING STOP FAILED — WAV FINALIZATION TIMEOUT',
      );
    } finally {
      if (identical(_recorderStopCompleter, stopCompleter)) {
        _recorderStopCompleter = null;
      }
    }
  }

  @override
  Future<void> exportRecording(BrowserRecordingArtifact artifact) async {
    final recorderWorker = _recorderWorker;
    final finalized = _lastRecordingArtifact;
    if (recorderWorker == null || finalized == null) {
      throw const BrowserRecordingException(
        BrowserRecordingFailure.exportFailed,
        'WAV EXPORT UNAVAILABLE — NO FINALIZED RECORDING',
      );
    }

    final exportCompleter = Completer<web.Blob>();
    _recorderExportCompleter = exportCompleter;
    recorderWorker.postMessage(
      <String, Object?>{'type': 'export'}.jsify(),
    );

    try {
      // Await the recordingExport message from the Worker.
      final blob = await _recorderExportCompleter!.future.timeout(
        _recorderExportTimeout,
      );
      final objectUrl = web.URL.createObjectURL(blob);
      final anchor = web.HTMLAnchorElement()
        ..href = objectUrl
        ..download = artifact.fileName;
      web.document.body?.appendChild(anchor);
      try {
        anchor.click();
      } finally {
        anchor.remove();
        web.URL.revokeObjectURL(objectUrl);
      }
    } on TimeoutException {
      throw const BrowserRecordingException(
        BrowserRecordingFailure.exportFailed,
        'WAV EXPORT FAILED — RECORDER WORKER TIMEOUT',
      );
    } finally {
      if (identical(_recorderExportCompleter, exportCompleter)) {
        _recorderExportCompleter = null;
      }
    }
  }

  @override
  Future<void> stop() async {
    final sourceNode = _sourceNode;
    final workletNode = _workletNode;
    final destinationNode = _destinationNode;
    final recorderWorker = _recorderWorker;
    final context = _context;

    _sourceNode = null;
    _workletNode = null;
    _destinationNode = null;
    _recorderWorker = null;
    _context = null;
    _recordingActive = false;

    sourceNode?.disconnect();
    if (workletNode != null) {
      _setWorkletRecording(workletNode, enabled: false);
      workletNode.disconnect();
    }
    destinationNode?.disconnect();

    if (recorderWorker != null) {
      final stopCompleter = Completer<BrowserRecordingArtifact>();
      _recorderStopCompleter = stopCompleter;
      recorderWorker.postMessage(
        <String, Object?>{'type': 'stop'}.jsify(),
      );
      try {
        await stopCompleter.future.timeout(_recorderStopTimeout);
      } on Object {
        // Fail closed: graph teardown cannot be blocked by recorder shutdown.
      } finally {
        if (identical(_recorderStopCompleter, stopCompleter)) {
          _recorderStopCompleter = null;
        }
      }
      recorderWorker.terminate();
    }

    _recorderStartCompleter = null;
    _recorderExportCompleter = null;

    if (context != null) {
      try {
        await context.close().toDart;
      } on Object {
        // Stopping remains idempotent even if the browser already closed it.
      }
    }
  }

  int _recorderMaxOutstandingPcm(num sampleRate) {
    final framesInBudget =
        sampleRate * _recorderBackpressureBudgetMilliseconds / 1000;
    return (framesInBudget / _recorderRenderQuantumFrames)
        .ceil()
        .clamp(1, 4096)
        .toInt();
  }

  void _setWorkletRecording(
    web.AudioWorkletNode workletNode, {
    required bool enabled,
    int? maxOutstandingPcm,
  }) {
    final message = <String, Object?>{
      'type': 'recording',
      'enabled': enabled,
    };
    if (maxOutstandingPcm != null) {
      message['maxOutstandingPcm'] = maxOutstandingPcm;
    }
    workletNode.port.postMessage(message.jsify());
  }

  void _failPendingRecordingOperations(BrowserRecordingException failure) {
    final startCompleter = _recorderStartCompleter;
    if (startCompleter != null && !startCompleter.isCompleted) {
      startCompleter.completeError(failure);
    }
    final stopCompleter = _recorderStopCompleter;
    if (stopCompleter != null && !stopCompleter.isCompleted) {
      stopCompleter.completeError(failure);
    }
    final exportCompleter = _recorderExportCompleter;
    if (exportCompleter != null && !exportCompleter.isCompleted) {
      exportCompleter.completeError(failure);
    }
  }

  void _notifyRecordingFailure(BrowserRecordingException failure) {
    _recordingFailureHandler?.call(failure);
  }

  BrowserRecordingException _workerRecordingFailure(JSAny? message) {
    switch (_messageString(message, 'failureCode')) {
      case 'storageFull':
        return const BrowserRecordingException(
          BrowserRecordingFailure.storageFull,
          'RECORDING FAILED — STORAGE FULL',
        );
      case 'exportFailed':
        return const BrowserRecordingException(
          BrowserRecordingFailure.exportFailed,
          'WAV EXPORT FAILED — FINALIZED RECORDING UNAVAILABLE',
        );
      case 'writeFailed':
      default:
        return const BrowserRecordingException(
          BrowserRecordingFailure.writeFailed,
          'RECORDING FAILED — WAV WRITE FAILED',
        );
    }
  }

  String? _messageType(JSAny? message) => _messageString(message, 'type');

  String? _messageString(JSAny? message, String key) {
    if (message == null) {
      return null;
    }
    try {
      return (message as JSObject)[key]?.dartify()?.toString();
    } on Object {
      return null;
    }
  }

  int _messageInt(JSAny? message, String key) {
    if (message == null) {
      return 0;
    }
    try {
      final value = (message as JSObject)[key]?.dartify();
      return value is num ? value.toInt() : 0;
    } on Object {
      return 0;
    }
  }

  web.Blob? _messageBlob(JSAny? message, String key) {
    if (message == null) {
      return null;
    }
    try {
      final value = (message as JSObject)[key];
      return value == null ? null : value as web.Blob;
    } on Object {
      return null;
    }
  }

  String _sanitize(Object error) {
    final compact = error
        .toString()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(
          RegExp(r'(?i)(token|password|authorization)=?[^ ,;]+'),
          r'$1=[REDACTED]',
        )
        .trim();
    return compact.isEmpty ? 'UNKNOWN ERROR' : compact;
  }
}
