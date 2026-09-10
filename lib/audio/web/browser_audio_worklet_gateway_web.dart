import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'browser_audio_processing_controller.dart';
import 'browser_capture_controller.dart';

typedef BrowserActiveStreamProvider = web.MediaStream? Function();

class WebAudioWorkletGateway implements BrowserAudioProcessingGateway {
  WebAudioWorkletGateway({required BrowserActiveStreamProvider activeStream})
      : _activeStream = activeStream;

  final BrowserActiveStreamProvider _activeStream;

  web.AudioContext? _context;
  web.MediaStreamAudioSourceNode? _sourceNode;
  web.AudioWorkletNode? _workletNode;
  web.MediaStreamAudioDestinationNode? _destinationNode;

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
    try {
      await context.audioWorklet.addModule('audio/livemixmaster-worklet.js').toDart;

      final sourceNode = context.createMediaStreamSource(stream);
      final workletNode = web.AudioWorkletNode(context, 'livemixmaster-dsp');
      final destinationNode = context.createMediaStreamDestination();

      sourceNode.connect(workletNode);
      workletNode.connect(destinationNode);
      await context.resume().toDart;

      _context = context;
      _sourceNode = sourceNode;
      _workletNode = workletNode;
      _destinationNode = destinationNode;

      return const BrowserAudioProcessingAttempt.started();
    } on Object catch (error) {
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
    final context = _context;

    _sourceNode = null;
    _workletNode = null;
    _destinationNode = null;
    _context = null;

    sourceNode?.disconnect();
    workletNode?.disconnect();
    destinationNode?.disconnect();

    if (context != null) {
      try {
        await context.close().toDart;
      } on Object {
        // Stopping remains idempotent even if the browser already closed it.
      }
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
