import 'dart:async';
import 'dart:io';

import 'reliability_models.dart';
import 'session_tracklist_codec.dart';
import 'session_tracklist_repository.dart';

class SessionTracklistStore implements SessionTracklistRepository {
  SessionTracklistStore({required this.file, SessionTracklistCodec? codec})
      : _codec = codec ?? const SessionTracklistCodec();

  final File file;
  final SessionTracklistCodec _codec;
  final StreamController<ServiceStatus> _statuses =
      StreamController<ServiceStatus>.broadcast();

  @override
  Stream<ServiceStatus> get onStatus => _statuses.stream;

  @override
  Future<List<TracklistEntry>> load() async {
    _emit(const ServiceStatus.running());
    try {
      final primary = await _tryDecode(file);
      if (primary != null) {
        _emit(const ServiceStatus.succeeded());
        return primary;
      }
      final backup = File('${file.path}.bak');
      final recovered = await _tryDecode(backup);
      if (recovered != null) {
        _emit(const ServiceStatus.succeeded());
        return recovered;
      }
      if (!await file.exists() && !await backup.exists()) {
        _emit(const ServiceStatus.succeeded());
        return const <TracklistEntry>[];
      }
      throw const FormatException('Saved tracklist is invalid');
    } on FormatException {
      _emit(
        const ServiceStatus.failed(
          failureCode: ServiceFailureCode.malformedResponse,
          message: 'Saved tracklist is invalid',
        ),
      );
      rethrow;
    } on FileSystemException {
      _emit(
        const ServiceStatus.failed(
          failureCode: ServiceFailureCode.writeFailed,
          message: 'Saved tracklist could not be read',
        ),
      );
      rethrow;
    }
  }

  @override
  Future<void> save(Iterable<TracklistEntry> entries) async {
    _emit(const ServiceStatus.running());
    final temporary = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    try {
      await file.parent.create(recursive: true);
      await temporary.writeAsString(_codec.encode(entries), flush: true);
      if (await backup.exists()) await backup.delete();
      if (await file.exists()) await file.rename(backup.path);
      await temporary.rename(file.path);
      if (await backup.exists()) await backup.delete();
      _emit(const ServiceStatus.succeeded());
    } on FileSystemException {
      _emit(
        const ServiceStatus.failed(
          failureCode: ServiceFailureCode.writeFailed,
          message: 'Tracklist could not be saved',
        ),
      );
      rethrow;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<List<TracklistEntry>?> _tryDecode(File candidate) async {
    if (!await candidate.exists()) return null;
    try {
      return _codec.decode(await candidate.readAsString());
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> dispose() => _statuses.close();

  void _emit(ServiceStatus status) {
    if (!_statuses.isClosed) _statuses.add(status);
  }
}
