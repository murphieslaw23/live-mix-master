import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'browser_audio_processing_controller.dart';
import 'browser_capture_controller.dart';

typedef BrowserActiveStreamProvider = web.MediaStream? Function();

const int _recorderMaxBytes = 64 * 1024 * 1024;

class WebAudioWorkletGateway implements BrowserAudioProcessingGateway {
  WebAudioWorkletGateway({required BrowserActiveStreamProvider activeStream})
      : _activeStream = activeStream;

  final BrowserActiveStreamProvider _activeStream;

  web.AudioContext? _context;
  web.MediaStreamAudioSourceNode? _sourceNode;
  web.AudioWorkletNode? _workletNode;
  web.MediaStreamAudioDestinationNode? _destinationNode;
  web.Worker? _recorderWorker;

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
              workletNode.port.postMessage(
                <String, Object?>{'type': 'telemetryAck'}.jsify(),
              );
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
            case 'recordingError':
              workletNode.port.postMessage(
                <String, Object?>{
                  'type': 'recording',
                  'enabled': false,
                }.jsify(),
              );
              break;
            default:
              break;
          }
        }).toJS,
      );

      recorderWorker.postMessage(
        <String, Object?>{
          'type': 'start',
          'sampleRate': context.sampleRate.round(),
          'channels': 2,
          'sampleFormat': 'pcm24',
          'maxBytes': _recorderMaxBytes,
        }.jsify(),
      );

      sourceNode.connect(workletNode);
      workletNode.connect(destinationNode);
      await context.resume().toDart;

      _context = context;
      _sourceNode = sourceNode;
      _workletNode = workletNode;
      _destinationNode = destinationNode;
      _recorderWorker = recorderWorker;

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

    sourceNode?.disconnect();
    workletNode?.disconnect();
    destinationNode?.disconnect();
    if (recorderWorker != null) {
      recorderWorker.terminate();
    }

    if (context != null) {
      try {
        await context.close().toDart;
      } on Object {
        // Stopping remains idempotent even if the browser already closed it.
      }
    }
  }

  String? _messageType(JSAny? message) {
    if (message == null) {
      return null;
    }
    try {
      return (message as JSObject)['type']?.dartify()?.toString();
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
