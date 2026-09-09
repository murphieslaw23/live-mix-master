import 'dart:convert';

import 'reliability_models.dart';
import 'session_tracklist_codec.dart';

enum ExportFormat { csv, json, m3u }

/// Exports durable session tracklist records to CSV, JSON, and M3U formats.
/// Operates directly on persisted TracklistEntry domain models.
class TracklistExporter {
  const TracklistExporter({SessionTracklistCodec? jsonCodec})
      : _jsonCodec = jsonCodec ?? const SessionTracklistCodec();

  final SessionTracklistCodec _jsonCodec;

  String export({
    required Iterable<TracklistEntry> entries,
    required ExportFormat format,
    String? sessionName,
    DateTime? exportedAt,
  }) {
    switch (format) {
      case ExportFormat.csv:
        return toCsv(entries);
      case ExportFormat.json:
        return toJson(entries, sessionName: sessionName, exportedAt: exportedAt);
      case ExportFormat.m3u:
        return toM3u(entries);
    }
  }

  /// Exports entries as RFC 4180 compliant CSV.
  /// Escapes commas, quotes, and newlines in text fields.
  String toCsv(Iterable<TracklistEntry> entries) {
    final buffer = StringBuffer();
    buffer.writeln('Cue Time,Artist,Title,Source,Confidence,Provenance');
    for (final entry in entries) {
      final cue = _formatDuration(entry.cueTime);
      final artist = _escapeCsv(entry.artist);
      final title = _escapeCsv(entry.title);
      final source = _escapeCsv(entry.sourceId);
      final confidence = (entry.confidence * 100).toStringAsFixed(1);
      final provenance = entry.provenance.name;
      buffer.writeln('$cue,$artist,$title,$source,$confidence%,$provenance');
    }
    return buffer.toString();
  }

  /// Exports full persisted tracklist schema plus export metadata as JSON.
  String toJson(
    Iterable<TracklistEntry> entries, {
    String? sessionName,
    DateTime? exportedAt,
  }) {
    final now = exportedAt ?? DateTime.now().toUtc();
    final decodedEntries = jsonDecode(_jsonCodec.encode(entries))['entries'];
    final document = <String, dynamic>{
      'exportVersion': 1,
      'exportedAt': now.toIso8601String(),
      if (sessionName != null) 'sessionName': sessionName,
      'trackCount': entries.length,
      'entries': decodedEntries,
    };
    return const JsonEncoder.withIndent('  ').convert(document);
  }

  /// Exports standard extended M3U with cue time annotations.
  /// Sanitizes any newlines in artist/title into spaces to preserve #EXTINF structure.
  /// Does not invent synthetic media locations.
  String toM3u(Iterable<TracklistEntry> entries) {
    final buffer = StringBuffer();
    buffer.writeln('#EXTM3U');
    for (final entry in entries) {
      final seconds = entry.cueTime.inSeconds;
      final artist = entry.artist.replaceAll(RegExp(r'[\r\n]+'), ' ');
      final title = entry.title.replaceAll(RegExp(r'[\r\n]+'), ' ');
      buffer.writeln('#EXTINF:$seconds,$artist - $title');
      buffer.writeln('#CUE:${_formatDuration(entry.cueTime)}');
    }
    return buffer.toString();
  }

  static String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  static String _escapeCsv(String field) {
    if (field.contains(',') ||
        field.contains('"') ||
        field.contains('\n') ||
        field.contains('\r')) {
      final escaped = field.replaceAll('"', '""');
      return '"$escaped"';
    }
    return field;
  }
}
