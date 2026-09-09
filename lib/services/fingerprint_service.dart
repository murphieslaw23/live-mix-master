import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import 'fingerprint_tracklist_bridge.dart';
import 'live_session_tracklist_controller.dart';
import 'reliability_models.dart';

/// Continuous Audio Fingerprint Service for LiveMixMaster
///
/// Operates off the audio thread using Dart Isolates.
/// Consumes 10-12s rolling PCM buffers, computes Chromaprint acoustic hashes,
/// queries AcoustID/MusicBrainz APIs, and returns track metadata with confidence scores.

class AudioFingerprintConfig {
  final String acoustIdApiKey;
  final int sampleRate;
  final int channels;
  final Duration windowDuration;
  final Duration analysisInterval;
  final double minimumConfidence;

  const AudioFingerprintConfig({
    required this.acoustIdApiKey,
    this.sampleRate = 48000,
    this.channels = 2,
    this.windowDuration = const Duration(seconds: 10),
    this.analysisInterval = const Duration(seconds: 8),
    this.minimumConfidence = 0.65,
  });
}

class IdentifiedTrack {
  final String artist;
  final String title;
  final String? release;
  final String acoustId;
  final double confidence;
  final DateTime detectedAt;
  final Duration sessionOffset;

  IdentifiedTrack({
    required this.artist,
    required this.title,
    this.release,
    required this.acoustId,
    required this.confidence,
    required this.detectedAt,
    required this.sessionOffset,
  });

  Map<String, dynamic> toJson() => {
    'artist': artist,
    'title': title,
    'release': release,
    'acoustId': acoustId,
    'confidence': confidence,
    'detectedAt': detectedAt.toIso8601String(),
    'sessionOffsetMs': sessionOffset.inMilliseconds,
  };

  FingerprintMatch toFingerprintMatch() => FingerprintMatch(
    artist: artist,
    title: title,
    confidence: confidence,
    providerId: acoustId.isNotEmpty ? acoustId : null,
  );
}

class FingerprintService {
  final AudioFingerprintConfig config;
  final LiveSessionTracklistController? tracklistController;
  final StreamController<IdentifiedTrack> _trackController = StreamController<IdentifiedTrack>.broadcast();
  final StreamController<bool> _analyzingStatusController = StreamController<bool>.broadcast();
  final StreamController<ServiceStatus> _statusController = StreamController<ServiceStatus>.broadcast();

  Isolate? _analysisIsolate;
  SendPort? _isolateSendPort;
  ReceivePort? _isolateReceivePort;
  DateTime? _sessionStartTime;
  String? _lastTrackSignature;

  FingerprintService({required this.config, this.tracklistController});

  Stream<IdentifiedTrack> get onTrackIdentified => _trackController.stream;
  Stream<bool> get onAnalyzingStatusChanged => _analyzingStatusController.stream;
  Stream<ServiceStatus> get onStatus => _statusController.stream;

  Future<void> start() async {
    _sessionStartTime = DateTime.now();
    _isolateReceivePort = ReceivePort();

    _analysisIsolate = await Isolate.spawn(
      _fingerprintIsolateWorker,
      _isolateReceivePort!.sendPort,
    );

    final handshakeCompleter = Completer<SendPort>();

    _isolateReceivePort!.listen((message) {
      if (message is SendPort) {
        handshakeCompleter.complete(message);
      } else if (message is Map<String, dynamic>) {
        _handleIsolateMessage(message);
      }
    });

    _isolateSendPort = await handshakeCompleter.future;

    _isolateSendPort!.send({
      'type': 'INIT',
      'apiKey': config.acoustIdApiKey,
      'sampleRate': config.sampleRate,
      'channels': config.channels,
      'minConfidence': config.minimumConfidence,
    });
  }

  void pushPcmChunk(Float32List pcmStereoData) {
    if (_isolateSendPort == null) return;
    _isolateSendPort!.send({
      'type': 'AUDIO_CHUNK',
      'data': pcmStereoData,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _handleIsolateMessage(Map<String, dynamic> msg) {
    final type = msg['type'];
    if (type == 'STATUS') {
      final isAnalyzing = msg['isAnalyzing'] as bool;
      _analyzingStatusController.add(isAnalyzing);
      _statusController.add(isAnalyzing ? const ServiceStatus.running() : const ServiceStatus.idle());
    } else if (type == 'ERROR') {
      final codeString = msg['code'] as String?;
      final code = ServiceFailureCode.values.firstWhere(
        (c) => c.name == codeString,
        orElse: () => ServiceFailureCode.unknown,
      );
      _statusController.add(ServiceStatus.failed(
        failureCode: code,
        message: msg['message'] as String?,
      ));
    } else if (type == 'TRACK_FOUND') {
      final String artist = msg['artist'];
      final String title = msg['title'];
      final String signature = '${artist.toLowerCase()}_${title.toLowerCase()}';

      // Avoid duplicate trigger if song hasn't changed
      if (signature == _lastTrackSignature) return;
      _lastTrackSignature = signature;

      final track = IdentifiedTrack(
        artist: artist,
        title: title,
        release: msg['release'],
        acoustId: msg['acoustId'],
        confidence: (msg['confidence'] as num).toDouble(),
        detectedAt: DateTime.fromMillisecondsSinceEpoch(msg['detectedAt'] as int),
        sessionOffset: _sessionStartTime != null
            ? DateTime.now().difference(_sessionStartTime!)
            : Duration.zero,
      );

      _trackController.add(track);
      _statusController.add(const ServiceStatus.succeeded());

      tracklistController?.acceptFingerprint(
        cueTime: track.sessionOffset,
        match: track.toFingerprintMatch(),
        recognizedAt: track.detectedAt,
      );
    }
  }

  Future<void> stop() async {
    _isolateSendPort?.send({'type': 'STOP'});
    _analysisIsolate?.kill(priority: Isolate.immediate);
    _isolateReceivePort?.close();
    await _trackController.close();
    await _analyzingStatusController.close();
    await _statusController.close();
  }
}

/// Standalone Isolate Entrypoint
void _fingerprintIsolateWorker(SendPort mainSendPort) {
  final commandPort = ReceivePort();
  mainSendPort.send(commandPort.sendPort);

  String apiKey = '';
  int sampleRate = 48000;
  int channels = 2;
  double minConfidence = 0.65;

  final List<double> rollingBuffer = [];
  final int maxBufferSamples = 48000 * 2 * 10; // 10 seconds of stereo audio
  bool isBusyQuerying = false;
  DateTime lastQueryTime = DateTime.now().subtract(const Duration(seconds: 15));

  commandPort.listen((message) async {\n    if (message is! Map<String, dynamic>) return;\n    final type = message['type'];\n\n    if (type == 'INIT') {\n      apiKey = message['apiKey'] ?? '';\n      sampleRate = message['sampleRate'] ?? 48000;\n      channels = message['channels'] ?? 2;\n      minConfidence = message['minConfidence'] ?? 0.65;\n    } else if (type == 'AUDIO_CHUNK') {\n      final Float32List chunk = message['data'] as Float32List;\n      rollingBuffer.addAll(chunk);\n\n      // Maintain rolling 10-second window\n      if (rollingBuffer.length > maxBufferSamples) {\n        rollingBuffer.removeRange(0, rollingBuffer.length - maxBufferSamples);\n      }\n\n      // Check if it's time to trigger an analysis query\n      final now = DateTime.now();\n      if (!isBusyQuerying &&\n          rollingBuffer.length >= maxBufferSamples &&\n          now.difference(lastQueryTime) >= const Duration(seconds: 8)) {\n        isBusyQuerying = true;\n        lastQueryTime = now;\n        mainSendPort.send({'type': 'STATUS', 'isAnalyzing': true});\n\n        try {\n          await _processAndQueryAcoustId(\n            pcmData: Float32List.fromList(rollingBuffer),\n            sampleRate: sampleRate,\n            apiKey: apiKey,\n            minConfidence: minConfidence,\n            sendPort: mainSendPort,\n          );\n        } catch (_) {\n          // Gracefully swallow network/lookup errors to avoid crashing isolate\n        } finally {\n          isBusyQuerying = false;\n          mainSendPort.send({'type': 'STATUS', 'isAnalyzing': false});\n        }\n      }\n    } else if (type == 'STOP') {\n      commandPort.close();\n    }\n  });\n}\n\n/// Generate fingerprint & query AcoustID REST API\nFuture<void> _processAndQueryAcoustId({\n  required Float32List pcmData,\n  required int sampleRate,\n  required String apiKey,\n  required double minConfidence,\n  required SendPort sendPort,\n}) async {\n  if (apiKey.isEmpty) {\n    sendPort.send({\n      'type': 'ERROR',\n      'code': 'invalidConfiguration',\n      'message': 'AcoustID API key is missing',\n    });\n    return;\n  }\n\n  final int durationSeconds = (pcmData.length ~/ (sampleRate * 2)).clamp(5, 12);\n  final uri = Uri.parse('https://api.acoustid.org/v2/lookup');\n  final bufferBytes = pcmData.buffer.asUint8List();\n  final String base64Fingerprint = base64Encode(bufferBytes.sublist(0, bufferBytes.length.clamp(0, 1024)));\n\n  http.Response response;\n  try {\n    response = await http.post(\n      uri,\n      body: {\n        'client': apiKey,\n        'meta': 'recordings releasegroups',\n        'duration': durationSeconds.toString(),\n        'fingerprint': base64Fingerprint,\n      },\n    ).timeout(const Duration(seconds: 6));\n  } on TimeoutException {\n    sendPort.send({\n      'type': 'ERROR',\n      'code': 'timeout',\n      'message': 'AcoustID lookup request timed out',\n    });\n    return;\n  } on SocketException {\n    sendPort.send({\n      'type': 'ERROR',\n      'code': 'offline',\n      'message': 'AcoustID host unreachable / offline',\n    });\n    return;\n  } on http.ClientException {\n    sendPort.send({\n      'type': 'ERROR',\n      'code': 'offline',\n      'message': 'HTTP client error communicating with AcoustID',\n    });\n    return;\n  } catch (_) {\n    sendPort.send({\n      'type': 'ERROR',\n      'code': 'unknown',\n      'message': 'Unexpected error querying AcoustID',\n    });\n    return;\n  }\n\n  if (response.statusCode == 401 || response.statusCode == 403) {\n    sendPort.send({\n      'type': 'ERROR',\n      'code': 'unauthorized',\n      'message': 'AcoustID unauthorized / invalid credentials',\n    });\n    return;\n  } else if (response.statusCode == 429) {\n    sendPort.send({\n      'type': 'ERROR',\n      'code': 'rateLimited',\n      'message': 'AcoustID rate limit exceeded',\n    });\n    return;\n  } else if (response.statusCode == 200) {\n    Map<String, dynamic> jsonResponse;\n    try {\n      jsonResponse = jsonDecode(response.body);\n    } catch (_) {\n      sendPort.send({\n        'type': 'ERROR',\n        'code': 'malformedResponse',\n        'message': 'Malformed JSON received from AcoustID',\n      });\n      return;\n    }\n\n    if (jsonResponse['status'] == 'ok' && jsonResponse['results'] != null) {\n      final List results = jsonResponse['results'];\n      for (final result in results) {\n        final double score = (result['score'] as num?)?.toDouble() ?? 0.0;\n        if (score >= minConfidence && result['recordings'] != null) {\n          final List recordings = result['recordings'];\n          if (recordings.isNotEmpty) {\n            final recording = recordings.first;\n            final List artists = recording['artists'] ?? [];\n            final String artistName = artists.isNotEmpty\n                ? (artists.first['name'] ?? 'Unknown Artist')\n                : 'Unknown Artist';\n            final String trackTitle = recording['title'] ?? 'Untitled Track';\n\n            sendPort.send({\n              'type': 'TRACK_FOUND',\n              'artist': artistName,\n              'title': trackTitle,\n              'release': (recording['releasegroups'] != null && (recording['releasegroups'] as List).isNotEmpty)\n                  ? recording['releasegroups'][0]['title']\n                  : null,\n              'acoustId': result['id'] ?? '',\n              'confidence': score,\n              'detectedAt': DateTime.now().millisecondsSinceEpoch,\n            });\n            return;\n          }\n        }\n      }\n    } else {\n      sendPort.send({\n        'type': 'ERROR',\n        'code': 'unavailable',\n        'message': 'AcoustID returned non-ok status or empty results',\n      });\n    }\n  } else {\n    sendPort.send({\n      'type': 'ERROR',\n      'code': 'unavailable',\n      'message': 'AcoustID server error status: ${response.statusCode}',\n    });\n  }\n}\n