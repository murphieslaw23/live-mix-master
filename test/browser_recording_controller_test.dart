import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/web/browser_recording_controller.dart';

class FakeBrowserRecordingGateway
    implements BrowserRecordingGateway, BrowserRecordingLifecycleGateway {
  BrowserRecordingException? startFailure;
  BrowserRecordingException? stopFailure;
  BrowserRecordingException? exportFailure;
  BrowserRecordingArtifact artifact = const BrowserRecordingArtifact(
    fileName: 'acceptance.wav',
    bytesWritten: 50,
    dataBytes: 6,
  );

  int starts = 0;
  int stops = 0;
  int exports = 0;
  void Function(BrowserRecordingException failure)? _failureHandler;

  @override
  void setRecordingFailureHandler(
    void Function(BrowserRecordingException failure) handler,
  ) {
    _failureHandler = handler;
  }

  void emitFailure(BrowserRecordingException failure) {
    _failureHandler?.call(failure);
  }

  @override
  Future<void> startRecording() async {
    starts += 1;
    if (startFailure case final failure?) {
      throw failure;
    }
  }

  @override
  Future<BrowserRecordingArtifact> stopRecording() async {
    stops += 1;
    if (stopFailure case final failure?) {
      throw failure;
    }
    return artifact;
  }

  @override
  Future<void> exportRecording(BrowserRecordingArtifact artifact) async {
    exports += 1;
    if (exportFailure case final failure?) {
      throw failure;
    }
  }
}

void main() {
  group('BrowserRecordingController', () {
    test('exposes deterministic record, finalize and export operator states', () async {
      final gateway = FakeBrowserRecordingGateway();
      final controller = BrowserRecordingController(gateway: gateway);

      expect(controller.state.status, BrowserRecordingStatus.idle);
      expect(controller.state.artifact, isNull);

      await controller.startRecording();
      expect(gateway.starts, 1);
      expect(controller.state.status, BrowserRecordingStatus.recording);
      expect(controller.state.message, 'RECORDING ACTIVE — POST-MASTER PCM TO WAV');

      await controller.stopRecording();
      expect(gateway.stops, 1);
      expect(controller.state.status, BrowserRecordingStatus.readyToExport);
      expect(controller.state.artifact, gateway.artifact);
      expect(controller.state.message, 'WAV FINALIZED — acceptance.wav — 50 BYTES');

      await controller.exportRecording();
      expect(gateway.exports, 1);
      expect(controller.state.status, BrowserRecordingStatus.readyToExport);
      expect(controller.state.artifact, gateway.artifact);
      expect(controller.state.message, 'WAV DOWNLOAD REQUESTED — acceptance.wav');
    });

    test('fails closed with explicit storage and runtime errors', () async {
      final gateway = FakeBrowserRecordingGateway();
      final controller = BrowserRecordingController(gateway: gateway);

      gateway.startFailure = const BrowserRecordingException(
        BrowserRecordingFailure.notReady,
        'RECORDING UNAVAILABLE — AUDIOWORKLET NOT ACTIVE',
      );
      await controller.startRecording();
      expect(controller.state.status, BrowserRecordingStatus.error);
      expect(controller.state.message, 'RECORDING UNAVAILABLE — AUDIOWORKLET NOT ACTIVE');

      gateway.startFailure = null;
      await controller.startRecording();
      expect(controller.state.status, BrowserRecordingStatus.recording);

      gateway.stopFailure = const BrowserRecordingException(
        BrowserRecordingFailure.storageFull,
        'RECORDING FAILED — STORAGE FULL',
      );
      await controller.stopRecording();
      expect(controller.state.status, BrowserRecordingStatus.error);
      expect(controller.state.message, 'RECORDING FAILED — STORAGE FULL');
      expect(controller.state.artifact, isNull);
    });

    test('asynchronous worker/backpressure failure updates operator state and listeners', () async {
      final gateway = FakeBrowserRecordingGateway();
      final controller = BrowserRecordingController(gateway: gateway);
      final observed = <BrowserRecordingStatus>[];
      controller.addListener((state) => observed.add(state.status));

      await controller.startRecording();
      expect(controller.state.status, BrowserRecordingStatus.recording);

      gateway.emitFailure(
        const BrowserRecordingException(
          BrowserRecordingFailure.backpressure,
          'RECORDING FAILED — AUDIO BACKPRESSURE',
        ),
      );

      expect(controller.state.status, BrowserRecordingStatus.error);
      expect(controller.state.message, 'RECORDING FAILED — AUDIO BACKPRESSURE');
      expect(controller.state.artifact, isNull);
      expect(observed, contains(BrowserRecordingStatus.error));
    });
  });
}
