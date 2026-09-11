import 'dart:async';

import 'package:web/web.dart' as web;

import '../reliability_models.dart';
import '../session_tracklist_codec.dart';
import '../session_tracklist_repository.dart';

class BrowserSessionTracklistRepository implements SessionTracklistRepository {
  BrowserSessionTracklistRepository({
    this.storageKey = 'lmm.session.active',
    SessionTracklistCodec codec = const SessionTracklistCodec(),
  }) : _codec = codec;

  final String storageKey;
  final SessionTracklistCodec _codec;
  final StreamController<ServiceStatus> _statuses =
      StreamController<ServiceStatus>.broadcast();

  @override
  Stream<ServiceStatus> get onStatus => _statuses.stream;

  @override
  Future<List<TracklistEntry>> load() async {
    _emit(const ServiceStatus.running());
    try {
      final document = web.window.localStorage.getItem(storageKey);
      if (document == null || document.isEmpty) {
        _emit(const ServiceStatus.succeeded());
        return const <TracklistEntry>[];
      }
      final entries = _codec.decode(document);
      _emit(const ServiceStatus.succeeded());
      return entries;
    } on FormatException {
      _emit(
        const ServiceStatus.failed(
          failureCode: ServiceFailureCode.malformedResponse,
          message: 'Saved browser session is invalid',
        ),
      );
      rethrow;
    } on Object {
      _emit(
        const ServiceStatus.failed(
          failureCode: ServiceFailureCode.writeFailed,
          message: 'Saved browser session could not be read',
        ),
      );
      rethrow;
    }
  }

  @override
  Future<void> save(Iterable<TracklistEntry> entries) async {
    _emit(const ServiceStatus.running());
    try {
      web.window.localStorage.setItem(storageKey, _codec.encode(entries));
      _emit(const ServiceStatus.succeeded());
    } on Object {
      _emit(
        const ServiceStatus.failed(
          failureCode: ServiceFailureCode.writeFailed,
          message: 'Browser session could not be saved',
        ),
      );
      rethrow;
    }
  }

  @override
  Future<void> dispose() => _statuses.close();

  void _emit(ServiceStatus status) {
    if (!_statuses.isClosed) {
      _statuses.add(status);
    }
  }
}
