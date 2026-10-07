import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:live_mix_master/services/broadcast_metadata_adapter.dart';
import 'package:live_mix_master/services/fingerprint_service.dart';
import 'package:live_mix_master/services/reliability_models.dart';

class _Call {
  _Call(this.request);
  final http.BaseRequest request;
  final response = Completer<http.StreamedResponse>();
  void reply(int code) { if (!response.isCompleted) response.complete(http.StreamedResponse(const Stream<List<int>>.empty(), code)); }
}
class _GateClient extends http.BaseClient {
  _GateClient({this.honorAbort = true});
  final bool honorAbort;
  final calls = <_Call>[];
  int aborts = 0;
  int closes = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final call = _Call(request); calls.add(call);
    if (request is http.AbortableRequest) {
      request.abortTrigger?.then((_) {
        aborts++;
        if (honorAbort && !call.response.isCompleted) call.response.completeError(http.RequestAbortedException(request.url));
      });
    }
    return call.response.future;
  }
  @override
  void close() { closes++; }
}
Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 1000 && !condition(); i++) { await Future<void>.delayed(const Duration(milliseconds: 1)); }
  expect(condition(), isTrue);
}
IdentifiedTrack _track(String title) => IdentifiedTrack(artist: 'Artist', title: title, acoustId: 'fixture', confidence: .9, detectedAt: DateTime.utc(2026), sessionOffset: Duration.zero);
BroadcastMetadataAdapter _adapter(_GateClient client, {Future<void> Function(Duration)? sleeper}) => BroadcastMetadataAdapter(config: const BroadcastServerConfig(protocol: BroadcastProtocol.icecast), fingerprintStream: const Stream<IdentifiedTrack>.empty(), httpClient: client, sleeper: sleeper);

void registerBroadcastLifecycleTests() {
  group('A3/A4 lifecycle and latest-update ordering', () {
    test('A then B then C settles superseded jobs once and sends only C after A drains', () async {
      final client = _GateClient(honorAbort: false); final adapter = _adapter(client);
      final results = <BroadcastAdapterResult>[]; final events = <BroadcastOperationStatus>[];
      final sub = adapter.onResult.listen(results.add); final eventSub = adapter.onOperationStatus.listen(events.add);
      final a = adapter.sendMetadata(_track('A')); await _until(() => client.calls.length == 1);
      final b = adapter.sendMetadata(_track('B')); final c = adapter.sendMetadata(_track('C'));
      final ar = await a; final br = await b;
      expect(ar.state, ServiceOperationState.cancelled); expect(br.state, ServiceOperationState.cancelled); expect(br.supersededBy, greaterThan(br.operationId));
      expect(adapter.pendingOperationCount, 1); expect(client.calls, hasLength(1));
      client.calls.first.reply(200); await _until(() => client.calls.length == 2);
      expect(client.calls.last.request.url.queryParameters['song'], 'Artist - C');
      client.calls.last.reply(200); final cr = await c; expect(cr.succeeded, isTrue); expect(adapter.isConnected, isTrue);
      await adapter.dispose(); expect(results, hasLength(3)); expect(results.map((r) => r.operationId).toSet(), hasLength(3));
      for (final result in results) { expect(events.where((e) => e.operationId == result.operationId && e.status.isTerminal), hasLength(1)); }
      await sub.cancel(); await eventSub.cancel();
    });
    test('old late failure neither retries nor resets a newer success', () async {
      final client = _GateClient(honorAbort: false); final adapter = _adapter(client);
      final a = adapter.sendMetadata(_track('A')); await _until(() => client.calls.length == 1);
      final b = adapter.sendMetadata(_track('B')); expect((await a).state, ServiceOperationState.cancelled);
      client.calls.first.reply(503); await _until(() => client.calls.length == 2); client.calls.last.reply(200);
      expect((await b).succeeded, isTrue); expect(adapter.isConnected, isTrue); expect(client.calls, hasLength(2)); await adapter.dispose();
    });
    test('rapid updates are bounded before first dispatch', () async {
      final client = _GateClient(); final adapter = _adapter(client);
      final futures = [for (var i = 0; i < 100; i++) adapter.sendMetadata(_track('Track $i'))];
      expect(adapter.pendingOperationCount, 1); await _until(() => client.calls.length == 1); client.calls.single.reply(200);
      final results = await Future.wait(futures); expect(results.where((r) => r.succeeded), hasLength(1)); expect(results.last.succeeded, isTrue); expect(client.calls.single.request.url.queryParameters['song'], 'Artist - Track 99'); await adapter.dispose();
    });
    test('dispose aborts active request settles pending and preserves injected client ownership', () async {
      final client = _GateClient(); final adapter = _adapter(client);
      final a = adapter.sendMetadata(_track('A')); await _until(() => client.calls.length == 1);
      final b = adapter.sendMetadata(_track('B')); final closing = adapter.dispose();
      expect((await a).state, ServiceOperationState.cancelled); expect((await b).state, ServiceOperationState.cancelled); await closing;
      expect(client.aborts, greaterThanOrEqualTo(1)); expect(client.closes, 0); expect(client.calls, hasLength(1)); expect(adapter.isConnected, isFalse);
      expect((await adapter.sendMetadata(_track('Too late'))).state, ServiceOperationState.cancelled); expect(client.calls, hasLength(1)); expect(identical(adapter.dispose(), closing), isTrue);
    });
    test('owned client closes exactly once on repeated disposal', () async {
      final client = _GateClient();
      final adapter = BroadcastMetadataAdapter(config: const BroadcastServerConfig(protocol: BroadcastProtocol.icecast), fingerprintStream: const Stream<IdentifiedTrack>.empty(), clientFactory: () => client);
      final operation = adapter.sendMetadata(_track('A')); await _until(() => client.calls.length == 1);
      final first = adapter.dispose(); final second = adapter.dispose(); expect(identical(first, second), isTrue); await first; expect((await operation).state, ServiceOperationState.cancelled); expect(client.closes, 1);
    });
    test('supersession interrupts backoff and consumes late sleeper errors', () async {
      final sleep = Completer<void>(); var sleeping = false;
      final client = _GateClient(); final adapter = _adapter(client, sleeper: (_) { sleeping = true; return sleep.future; });
      final a = adapter.sendMetadata(_track('A')); await _until(() => client.calls.length == 1); client.calls.first.reply(503); await _until(() => sleeping);
      final b = adapter.sendMetadata(_track('B')); expect((await a).state, ServiceOperationState.cancelled); await _until(() => client.calls.length == 2); client.calls.last.reply(200);
      expect((await b).succeeded, isTrue); sleep.completeError(StateError('synthetic sleeper failure')); await Future<void>.delayed(Duration.zero); expect(client.calls, hasLength(2)); await adapter.dispose();
    });
    test('dispose interrupts backoff without waiting for injected sleeper', () async {
      final sleep = Completer<void>(); var sleeping = false;
      final client = _GateClient(); final adapter = _adapter(client, sleeper: (_) { sleeping = true; return sleep.future; });
      final operation = adapter.sendMetadata(_track('A')); await _until(() => client.calls.length == 1); client.calls.first.reply(503); await _until(() => sleeping);
      await adapter.dispose().timeout(const Duration(seconds: 1)); expect((await operation).state, ServiceOperationState.cancelled); expect(client.calls, hasLength(1)); sleep.complete();
    });
    test('status listener can dispose without synchronous stream reentrancy', () async {
      final client = _GateClient(); final adapter = _adapter(client); Future<void>? closing;
      final sub = adapter.onStatus.listen((status) { if (status.state == ServiceOperationState.running) closing = adapter.dispose(); });
      final result = await adapter.sendMetadata(_track('A')); expect(result.state, ServiceOperationState.cancelled); await closing; await sub.cancel();
    });
    test('timeout signals transport abort and returns typed failure', () async {
      final client = _GateClient();
      final adapter = BroadcastMetadataAdapter(config: const BroadcastServerConfig(protocol: BroadcastProtocol.icecast, maxRetries: 0, timeout: Duration(milliseconds: 10)), fingerprintStream: const Stream<IdentifiedTrack>.empty(), httpClient: client);
      final result = await adapter.sendMetadata(_track('A')); expect(result.failureCode, ServiceFailureCode.timeout); await adapter.dispose(); expect(client.aborts, greaterThanOrEqualTo(1)); expect(client.calls, hasLength(1));
    });
    test('late response from non-aborting injected client cannot emit success after stop', () async {
      final client = _GateClient(honorAbort: false); final adapter = _adapter(client); final results = <BroadcastAdapterResult>[]; final sub = adapter.onResult.listen(results.add);
      final operation = adapter.sendMetadata(_track('A')); await _until(() => client.calls.length == 1); final closing = adapter.dispose();
      expect((await operation).state, ServiceOperationState.cancelled); client.calls.first.reply(200); await closing; expect(results, hasLength(1)); expect(results.single.succeeded, isFalse); expect(adapter.isConnected, isFalse); await sub.cancel();
    });
    test('overlay cancellation retains ordering gate until old writer finishes', () async {
      final gate = Completer<void>(); final writes = <String>[];
      final adapter = BroadcastMetadataAdapter(config: const BroadcastServerConfig(protocol: BroadcastProtocol.obsHttpOverlay), fingerprintStream: const Stream<IdentifiedTrack>.empty(), overlayWriter: (_, content) async { writes.add(content); if (writes.length == 1) await gate.future; });
      final a = adapter.sendMetadata(_track('A')); await _until(() => writes.length == 1); final b = adapter.sendMetadata(_track('B'));
      expect((await a).state, ServiceOperationState.cancelled); expect(writes, hasLength(1)); gate.complete(); expect((await b).succeeded, isTrue); expect(writes, ['ARTIST — A', 'ARTIST — B']); await adapter.dispose();
    });
  });
}
