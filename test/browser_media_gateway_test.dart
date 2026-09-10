import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/web/browser_capture_controller.dart';
import 'package:live_mix_master/audio/web/browser_media_gateway.dart';

void main() {
  group('DefaultBrowserMediaGateway', () {
    test('maps low-level capability probe without inventing system audio', () async {
      final gateway = DefaultBrowserMediaGateway(
        client: _FakeClient(
          capabilities: const BrowserAudioCapabilities(
            mediaDevicesAvailable: true,
            microphoneCaptureAvailable: true,
            displayCaptureAvailable: true,
            systemAudioGuaranteed: false,
          ),
        ),
      );

      final capabilities = await gateway.probeCapabilities();

      expect(capabilities.microphoneCaptureAvailable, isTrue);
      expect(capabilities.displayCaptureAvailable, isTrue);
      expect(capabilities.systemAudioGuaranteed, isFalse);
    });

    test('maps successful microphone capture to connected source', () async {
      final gateway = DefaultBrowserMediaGateway(
        client: _FakeClient(
          microphoneResult: const BrowserRawCapture.success(
            id: 'origin-scoped-1',
            label: 'USB Interface',
            hasAudioTrack: true,
          ),
        ),
      );

      final attempt = await gateway.requestMicrophone();

      expect(attempt.status, BrowserCaptureAttemptStatus.connected);
      expect(attempt.source?.kind, BrowserCaptureKind.microphone);
      expect(attempt.source?.id, 'origin-scoped-1');
      expect(attempt.source?.label, 'USB Interface');
    });

    test('display stream without audio maps to no-audio-track', () async {
      final gateway = DefaultBrowserMediaGateway(
        client: _FakeClient(
          displayResult: const BrowserRawCapture.success(
            id: 'display-1',
            label: 'Shared tab',
            hasAudioTrack: false,
          ),
        ),
      );

      final attempt = await gateway.requestDisplayAudio();

      expect(attempt.status, BrowserCaptureAttemptStatus.noAudioTrack);
      expect(attempt.source, isNull);
    });

    test('NotAllowedError maps to permission denied', () async {
      final gateway = DefaultBrowserMediaGateway(
        client: _FakeClient(
          microphoneResult: const BrowserRawCapture.failure(
            errorName: 'NotAllowedError',
          ),
        ),
      );

      final attempt = await gateway.requestMicrophone();

      expect(attempt.status, BrowserCaptureAttemptStatus.permissionDenied);
    });

    test('unsupported browser API maps to unsupported', () async {
      final gateway = DefaultBrowserMediaGateway(
        client: _FakeClient(
          displayResult: const BrowserRawCapture.failure(
            errorName: 'NotSupportedError',
          ),
        ),
      );

      final attempt = await gateway.requestDisplayAudio();

      expect(attempt.status, BrowserCaptureAttemptStatus.unsupported);
    });

    test('ended track propagates into controller reconnect state', () async {
      final client = _FakeClient(
        microphoneResult: const BrowserRawCapture.success(
          id: 'origin-scoped-2',
          label: 'Mixer USB',
          hasAudioTrack: true,
        ),
      );
      final gateway = DefaultBrowserMediaGateway(client: client);
      final controller = BrowserCaptureController(gateway: gateway);

      await controller.requestMicrophone();
      expect(controller.state.status, BrowserCaptureStatus.active);

      client.endActiveTrack();

      expect(controller.state.status, BrowserCaptureStatus.reconnectRequired);
      expect(controller.state.source, isNull);
    });
  });
}

class _FakeClient implements BrowserMediaClient {
  _FakeClient({
    this.capabilities = const BrowserAudioCapabilities(
      mediaDevicesAvailable: true,
      microphoneCaptureAvailable: true,
      displayCaptureAvailable: true,
      systemAudioGuaranteed: false,
    ),
    this.microphoneResult = const BrowserRawCapture.failure(
      errorName: 'NotSupportedError',
    ),
    this.displayResult = const BrowserRawCapture.failure(
      errorName: 'NotSupportedError',
    ),
  });

  final BrowserAudioCapabilities capabilities;
  final BrowserRawCapture microphoneResult;
  final BrowserRawCapture displayResult;
  void Function()? _onEnded;

  @override
  Future<BrowserAudioCapabilities> probeCapabilities() async => capabilities;

  @override
  Future<BrowserRawCapture> requestMicrophone({required void Function() onEnded}) async {
    _onEnded = onEnded;
    return microphoneResult;
  }

  @override
  Future<BrowserRawCapture> requestDisplayAudio({required void Function() onEnded}) async {
    _onEnded = onEnded;
    return displayResult;
  }

  void endActiveTrack() => _onEnded?.call();
}
