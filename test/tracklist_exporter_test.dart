import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/services/reliability_models.dart';
import 'package:live_mix_master/services/tracklist_exporter.dart';

void main() {
  group('TracklistExporter Contract Tests', () {
    const exporter = TracklistExporter();

    final testEntries = [
      TracklistEntry(
        sessionId: 'session_berlin_01',
        sourceId: 'master_bus',
        cueTime: const Duration(minutes: 1, seconds: 25),
        artist: 'Underground Resistance',
        title: 'Transition',
        confidence: 0.965,
        provenance: TrackProvenance.automatic,
        createdAt: DateTime.utc(2026, 9, 8, 22, 1, 25),
      ),
      TracklistEntry(
        sessionId: 'session_berlin_01',
        sourceId: 'master_bus',
        cueTime: const Duration(minutes: 7, seconds: 40),
        artist: 'Jeff Mills, "The Wizard"',
        title: 'The Bells (Live "Mix", 2026)\nRemaster',
        confidence: 1.0,
        provenance: TrackProvenance.manual,
        createdAt: DateTime.utc(2026, 9, 8, 22, 7, 40),
        updatedAt: DateTime.utc(2026, 9, 8, 22, 8, 0),
      ),
    ];

    test('exports RFC 4180 compliant CSV and quotes special characters', () {
      final csv = exporter.toCsv(testEntries);
      final lines = const LineSplitter().convert(csv);

      expect(lines.first, 'Cue Time,Artist,Title,Source,Confidence,Provenance');
      expect(lines[1], '01:25,Underground Resistance,Transition,master_bus,96.5%,automatic');

      // Second entry contains quotes, comma, and newline; must be quoted properly
      expect(csv, contains('"Jeff Mills, ""The Wizard"""'));
      expect(csv, contains('"The Bells (Live ""Mix"", 2026)\nRemaster"'));
      expect(csv, contains('100.0%,manual'));
    });

    test('exports JSON document with metadata, stable keys, and ISO-8601 timestamps', () {
      final jsonString = exporter.toJson(
        testEntries,
        sessionName: 'Tresor Closing Set',
        exportedAt: DateTime.utc(2026, 9, 9, 4, 0),
      );

      final document = jsonDecode(jsonString) as Map<String, dynamic>;
      expect(document['exportVersion'], 1);
      expect(document['exportedAt'], '2026-09-09T04:00:00.000Z');
      expect(document['sessionName'], 'Tresor Closing Set');
      expect(document['trackCount'], 2);

      final entriesList = document['entries'] as List;
      expect(entriesList, hasLength(2));
      expect(entriesList[0]['artist'], 'Underground Resistance');
      expect(entriesList[0]['title'], 'Transition');
      expect(entriesList[0]['provenance'], 'automatic');
      expect(entriesList[1]['artist'], 'Jeff Mills, "The Wizard"');
      expect(entriesList[1]['provenance'], 'manual');
      expect(entriesList[1]['updatedAt'], '2026-09-08T22:08:00.000Z');
    });

    test('exports extended M3U without inventing synthetic media locations', () {
      final m3u = exporter.toM3u(testEntries);
      final lines = const LineSplitter().convert(m3u);

      expect(lines[0], '#EXTM3U');
      expect(lines[1], '#EXTINF:85,Underground Resistance - Transition');
      expect(lines[2], '#CUE:01:25');
      expect(lines[3], '#EXTINF:460,Jeff Mills, "The Wizard" - The Bells (Live "Mix", 2026)\nRemaster');
      expect(lines[4], '#CUE:07:40');

      // Must not contain fabricated file:/// paths
      expect(m3u, isNot(contains('file://')));
      expect(m3u, isNot(contains('.mp3')));
    });

    test('export facade routes correctly to requested format', () {
      final csv = exporter.export(entries: testEntries, format: ExportFormat.csv);
      final json = exporter.export(entries: testEntries, format: ExportFormat.json);
      final m3u = exporter.export(entries: testEntries, format: ExportFormat.m3u);

      expect(csv, startsWith('Cue Time,Artist,Title'));
      expect(json, contains('"exportVersion": 1'));
      expect(m3u, startsWith('#EXTM3U'));
    });
  });
}
