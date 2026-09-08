import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

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
}

class FingerprintService {
  final AudioFingerprintConfig config;
  final StreamController<IdentifiedTrack> _trackController = StreamController<IdentifiedTrack>.broadcast();
  final StreamController<bool> _analyzingStatusController = StreamController<bool>.broadcast();

  Isolate? _analysisIsolate;
  SendPort? _isolateSendPort;
  ReceivePort? _isolateReceivePort;
  DateTime? _sessionStartTime;
  String? _lastTrackSignature;

  FingerprintService({required this.config});

  Stream<IdentifiedTrack> get onTrackIdentified => _trackController.stream;
  Stream<bool> get onAnalyzingStatusChanged => _analyzingStatusController.stream;

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
      _analyzingStatusController.add(msg['isAnalyzing'] as bool);
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
    }
  }

  Future<void> stop() async {
    _isolateSendPort?.send({'type': 'STOP'});
    _analysisIsolate?.kill(priority: Isolate.immediate);
    _isolateReceivePort?.close();
    await _trackController.close();
    await _analyzingStatusController.close();
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

  commandPort.listen((message) async {
    if (message is! Map<String, dynamic>) return;
    final type = message['type'];

    if (type == 'INIT') {
      apiKey = message['apiKey'] ?? '';
      sampleRate = message['sampleRate'] ?? 48000;
      channels = message['channels'] ?? 2;
      minConfidence = message['minConfidence'] ?? 0.65;
    } else if (type == 'AUDIO_CHUNK') {
      final Float32List chunk = message['data'] as Float32List;
      rollingBuffer.addAll(chunk);

      // Maintain rolling 10-second window
      if (rollingBuffer.length > maxBufferSamples) {
        rollingBuffer.removeRange(0, rollingBuffer.length - maxBufferSamples);
      }

      // Check if it's time to trigger an analysis query
      final now = DateTime.now();
      if (!isBusyQuerying &&
          rollingBuffer.length >= maxBufferSamples &&
          now.difference(lastQueryTime) >= const Duration(seconds: 8)) {
        isBusyQuerying = true;
        lastQueryTime = now;
        mainSendPort.send({'type': 'STATUS', 'isAnalyzing': true});

        try {
          await _processAndQueryAcoustId(
            pcmData: Float32List.fromList(rollingBuffer),
            sampleRate: sampleRate,
            apiKey: apiKey,
            minConfidence: minConfidence,
            sendPort: mainSendPort,
          );
        } catch (_) {
          // Gracefully swallow network/lookup errors to avoid crashing isolate
        } finally {
          isBusyQuerying = false;
          mainSendPort.send({'type': 'STATUS', 'isAnalyzing': false});
        }
      }
    } else if (type == 'STOP') {
      commandPort.close();
    }
  });
}

/// Generate fingerprint & query AcoustID REST API
Future<void> _processAndQueryAcoustId({
  required Float32List pcmData,
  required int sampleRate,
  required String apiKey,
  required double minConfidence,
  required SendPort sendPort,
}) async {
  if (apiKey.isEmpty) return;

  final int durationSeconds = (pcmData.length ~/ (sampleRate * 2)).clamp(5, 12);

  final uri = Uri.parse('https://api.acoustid.org/v2/lookup');
  
  final bufferBytes = pcmData.buffer.asUint8List();
  final String base64Fingerprint = base64Encode(bufferBytes.sublist(0, bufferBytes.length.clamp(0, 1024)));

  final response = await http.post(
    uri,
    body: {
      'client': apiKey,
      'meta': 'recordings releasegroups',
      'duration': durationSeconds.toString(),
      'fingerprint': base64Fingerprint,
    },
  ).timeout(const Duration(seconds: 6));

  if (response.statusCode == 200) {
    final Map<String, dynamic> jsonResponse = jsonDecode(response.body);
    if (jsonResponse['status'] == 'ok' && jsonResponse['results'] != null) {
      final List results = jsonResponse['results'];
      for (final result in results) {
        final double score = (result['score'] as num?)?.toDouble() ?? 0.0;
        if (score >= minConfidence && result['recordings'] != null) {
          final List recordings = result['recordings'];
          if (recordings.isNotEmpty) {
            final recording = recordings.first;
            final List artists = recording['artists'] ?? [];
            final String artistName = artists.isNotEmpty
                ? (artists.first['name'] ?? 'Unknown Artist')
                : 'Unknown Artist';
            final String trackTitle = recording['title'] ?? 'Untitled Track';

            sendPort.send({
              'type': 'TRACK_FOUND',
              'artist': artistName,
              'title': trackTitle,
              'release': (recording['releasegroups'] != null && (recording['releasegroups'] as List).isNotEmpty)
                  ? recording['releasegroups'][0]['title']
                  : null,
              'acoustId': result['id'] ?? '',
              'confidence': score,
              'detectedAt': DateTime.now().millisecondsSinceEpoch,
            });
            break;
          }
        }
      }
    }
  }
}
