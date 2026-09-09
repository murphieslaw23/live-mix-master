import 'dart:async';
import 'dart:io';

import 'reliability_models.dart';
import 'session_tracklist_codec.dart';

class SessionTracklistStore {
  SessionTracklistStore({required this.file, SessionTracklistCodec? codec})
      : _codec = codec ?? const SessionTracklistCodec();

  final File file;
  final SessionTracklistCodec _codec;
  final StreamController<ServiceStatus> _statuses = StreamController<ServiceStatus>.broadcast();

  Stream<ServiceStatus> get onStatus => _statuses.stream;

  Future<List<TracklistEntry>> load() async {
    _emit(const ServiceStatus.running());
    try {
      if (!await file.exists()) {
        _emit(const ServiceStatus.succeeded());
        return const [];
      }
      final entries = _codec.decode(await file.readAsString());
      _emit(const ServiceStatus.succeeded());
      return entries;
    } on FormatException {
      _emit(const ServiceStatus.failed(
        failureCode: ServiceFailureCode.malformedResponse,
        message: 'Saved tracklist is invalid',
      ));
      rethrow;
    } on FileSystemException {
      _emit(const ServiceStatus.failed(
        failureCode: ServiceFailureCode.writeFailed,
        message: 'Saved tracklist could not be read',
      ));
      rethrow;
    }
  }

  Future<void> save(Iterable<TracklistEntry> entries) async {
    _emit(const ServiceStatus.running());
    final temporary = File('${file.path}.tmp');
    try {
      await file.parent.create(recursive: true);
      await temporary.writeAsString(_codec.encode(entries), flush: true);
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
      _emit(const ServiceStatus.succeeded());
    } on FileSystemException {
      _emit(const ServiceStatus.failed(
        failureCode: ServiceFailureCode.writeFailed,
        message: 'Tracklist could not be saved',
      ));
      rethrow;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> dispose() => _statuses.close();

  void _emit(ServiceStatus status) {
    if (!_statuses.isClosed) _statuses.add(status);
  }
}
