import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/web/browser_capture_controller.dart';

void main() {
  test('operator disconnect stops the active stream and converges on reconnect-required', () async {
    final gateway = _DisconnectGateway();
    final controller = BrowserCaptureController(gateway: gateway);

    await controller.requestMicrophone();
    expect(controller.state.status, BrowserCaptureStatus.active);

    controller.disconnect();

    expect(gateway.disconnectCalls, 1);
    expect(controller.state.status, BrowserCaptureStatus.reconnectRequired);
    expect(controller.state.source, isNull);
    expect(controller.state.message, contains('CAPTURE ENDED'));
  });
}

class _DisconnectGateway
    implements BrowserMediaGateway, BrowserMediaDisconnectGateway {
  int disconnectCalls = 0;

  @override
  Future<BrowserAudioCapabilities> probeCapabilities() async {
    return const BrowserAudioCapabilities(
      mediaDevicesAvailable: true,
      microphoneCaptureAvailable: true,
      displayCaptureAvailable: true,
      systemAudioGuaranteed: false,
    );
  }

  @override
  Future<BrowserCaptureAttempt> requestMicrophone() async {
    return const BrowserCaptureAttempt.connected(
      BrowserCaptureSource(
        kind: BrowserCaptureKind.microphone,
        id: 'mic-test',
        label: 'USB INTERFACE',
      ),
    );
  }

  @override
  Future<BrowserCaptureAttempt> requestDisplayAudio() async {
    return const BrowserCaptureAttempt.noAudioTrack();
  }

  @override
  void disconnectActiveStream() {
    disconnectCalls += 1;
  }
}
