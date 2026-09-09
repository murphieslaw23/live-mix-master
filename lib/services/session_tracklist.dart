import 'reliability_models.dart';

class SessionTracklist {
  SessionTracklist({this.duplicateWindow = const Duration(seconds: 30)});

  final Duration duplicateWindow;
  final List<TracklistEntry> _entries = [];

  List<TracklistEntry> get entries => List.unmodifiable(_entries);

  bool addAutomatic(TracklistEntry candidate) {
    if (candidate.provenance != TrackProvenance.automatic) {
      throw ArgumentError.value(candidate.provenance, 'candidate.provenance', 'Automatic entries only');
    }
    if (shouldSuppressAutomaticMatch(candidate: candidate, existing: _entries, debounceWindow: duplicateWindow)) {
      return false;
    }
    final manualIndex = _entries.indexWhere((entry) =>
        entry.provenance == TrackProvenance.manual &&
        entry.sessionId == candidate.sessionId &&
        entry.sourceId == candidate.sourceId &&
        entry.cueTime == candidate.cueTime);
    if (manualIndex >= 0) return false;
    _entries.add(candidate);
    return true;
  }

  TracklistEntry correct({
    required int index,
    required String artist,
    required String title,
    required DateTime correctedAt,
  }) {
    if (index < 0 || index >= _entries.length) throw RangeError.index(index, _entries);
    final corrected = _entries[index].applyManualCorrection(artist: artist, title: title, correctedAt: correctedAt);
    _entries[index] = corrected;
    return corrected;
  }
}
