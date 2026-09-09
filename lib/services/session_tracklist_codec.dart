import 'dart:convert';

import 'reliability_models.dart';

class SessionTracklistCodec {
  const SessionTracklistCodec();

  String encode(Iterable<TracklistEntry> entries) => jsonEncode({
        'schemaVersion': 1,
        'entries': entries.map(_encodeEntry).toList(growable: false),
      });

  List<TracklistEntry> decode(String document) {
    final root = jsonDecode(document);
    if (root is! Map<String, dynamic> || root['schemaVersion'] != 1 || root['entries'] is! List) {
      throw const FormatException('Unsupported session tracklist document');
    }
    return (root['entries'] as List)
        .map((value) => _decodeEntry(value))
        .toList(growable: false);
  }

  Map<String, Object?> _encodeEntry(TracklistEntry entry) => {
        'sessionId': entry.sessionId,
        'sourceId': entry.sourceId,
        'cueTimeMilliseconds': entry.cueTime.inMilliseconds,
        'artist': entry.artist,
        'title': entry.title,
        'confidence': entry.confidence,
        'providerId': entry.providerId,
        'provenance': entry.provenance.name,
        'createdAt': entry.createdAt.toUtc().toIso8601String(),
        'updatedAt': entry.updatedAt?.toUtc().toIso8601String(),
      };

  TracklistEntry _decodeEntry(Object? value) {
    if (value is! Map<String, dynamic>) throw const FormatException('Invalid tracklist entry');
    final provenance = TrackProvenance.values.where((item) => item.name == value['provenance']).firstOrNull;
    final cue = value['cueTimeMilliseconds'];
    final confidence = value['confidence'];
    if (provenance == null || cue is! int || confidence is! num || value['sessionId'] is! String || value['sourceId'] is! String || value['artist'] is! String || value['title'] is! String || value['createdAt'] is! String) {
      throw const FormatException('Invalid tracklist entry fields');
    }
    return TracklistEntry(
      sessionId: value['sessionId'] as String,
      sourceId: value['sourceId'] as String,
      cueTime: Duration(milliseconds: cue),
      artist: value['artist'] as String,
      title: value['title'] as String,
      confidence: confidence.toDouble(),
      providerId: value['providerId'] as String?,
      provenance: provenance,
      createdAt: DateTime.parse(value['createdAt'] as String),
      updatedAt: value['updatedAt'] is String ? DateTime.parse(value['updatedAt'] as String) : null,
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
