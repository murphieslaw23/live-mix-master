import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../services/fingerprint_service.dart';

/// Broadcast Metadata Adapter for LiveMixMaster
///
/// Pushes newly identified track metadata (Artist — Title)
/// to Icecast/SHOUTcast servers, OBS WebSocket/HTTP overlays,
/// and external internet radio syndication APIs.

enum BroadcastProtocol { icecast, shoutcast, webhook, obsHttpOverlay }

class BroadcastServerConfig {
  final BroadcastProtocol protocol;
  final String host;
  final int port;
  final String mountPoint;
  final String adminUser;
  final String adminPassword;
  final Uri? webhookUrl;

  const BroadcastServerConfig({
    required this.protocol,
    required this.host,
    this.port = 8000,
    this.mountPoint = '/live',
    this.adminUser = 'admin',
    this.adminPassword = '',
    this.webhookUrl,
  });
}

class BroadcastMetadataAdapter {
  final BroadcastServerConfig config;
  final StreamSubscription<IdentifiedTrack>? _fingerprintSub;
  bool _isConnected = false;

  BroadcastMetadataAdapter({
    required this.config,
    required Stream<IdentifiedTrack> fingerprintStream,
  }) : _fingerprintSub = null {
    fingerprintStream.listen(_onTrackDetected);
  }

  bool get isConnected => _isConnected;

  Future<void> _onTrackDetected(IdentifiedTrack track) async {
    final String metadataSong = '${track.artist} - ${track.title}';
    
    switch (config.protocol) {
      case BroadcastProtocol.icecast:
        await _updateIcecastMetadata(metadataSong);
        break;
      case BroadcastProtocol.shoutcast:
        await _updateShoutcastMetadata(metadataSong);
        break;
      case BroadcastProtocol.webhook:
        await _sendWebhookMetadata(track);
        break;
      case BroadcastProtocol.obsHttpOverlay:
        await _updateLocalOverlayEndpoint(track);
        break;
    }
  }

  /// Sends admin metadata update request to Icecast 2
  Future<bool> _updateIcecastMetadata(String song) async {
    try {
      final uri = Uri(
        scheme: 'http',
        host: config.host,
        port: config.port,
        path: '/admin/metadata',
        queryParameters: {
          'mount': config.mountPoint,
          'mode': 'updinfo',
          'song': song,
          'charset': 'UTF-8',
        },
      );

      final basicAuth = 'Basic ' + base64Encode(utf8.encode('${config.adminUser}:${config.adminPassword}'));

      final response = await http.get(
        uri,
        headers: {'Authorization': basicAuth},
      ).timeout(const Duration(seconds: 4));

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Sends admin metadata update request to SHOUTcast DNAS
  Future<bool> _updateShoutcastMetadata(String song) async {
    try {
      final uri = Uri(
        scheme: 'http',
        host: config.host,
        port: config.port,
        path: '/admin.cgi',
        queryParameters: {
          'mode': 'updinfo',
          'pass': config.adminPassword,
          'song': song,
        },
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Dispatches full JSON payload to external webhooks (e.g. Discord, Telegram bot, SYCO23 API)
  Future<bool> _sendWebhookMetadata(IdentifiedTrack track) async {
    if (config.webhookUrl == null) return false;

    try {
      final response = await http.post(
        config.webhookUrl!,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'event': 'track_change',
          'artist': track.artist,
          'title': track.title,
          'release': track.release,
          'confidence': track.confidence,
          'detectedAt': track.detectedAt.toIso8601String(),
          'sessionOffsetMs': track.sessionOffset.inMilliseconds,
        }),
      ).timeout(const Duration(seconds: 5));

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// Writes local JSON or text file for OBS Text Source overlay
  Future<void> _updateLocalOverlayEndpoint(IdentifiedTrack track) async {
    try {
      final file = File('live_current_track.txt');
      await file.writeAsString('${track.artist.toUpperCase()} — ${track.title.toUpperCase()}');
    } catch (_) {}
  }

  void dispose() {
    _fingerprintSub?.cancel();
  }
}
