import 'browser_capture_controller.dart';

enum BrowserRawCaptureStatus {
  success,
  failure,
}

class BrowserRawCapture {
  const BrowserRawCapture._({
    required this.status,
    this.id,
    this.label,
    this.hasAudioTrack = false,
    this.errorName,
  });

  const BrowserRawCapture.success({
    required String id,
    required String label,
    required bool hasAudioTrack,
  }) : this._(
          status: BrowserRawCaptureStatus.success,
          id: id,
          label: label,
          hasAudioTrack: hasAudioTrack,
        );

  const BrowserRawCapture.failure({required String errorName})
      : this._(
          status: BrowserRawCaptureStatus.failure,
          errorName: errorName,
        );

  final BrowserRawCaptureStatus status;
  final String? id;
  final String? label;
  final bool hasAudioTrack;
  final String? errorName;
}

abstract interface class BrowserMediaClient {
  Future<BrowserAudioCapabilities> probeCapabilities();

  Future<BrowserRawCapture> requestMicrophone({
    required void Function() onEnded,
  });

  Future<BrowserRawCapture> requestDisplayAudio({
    required void Function() onEnded,
  });
}

abstract interface class BrowserMediaDeviceChangeClient {
  void setDeviceChangeHandler(void Function() handler);
}

class DefaultBrowserMediaGateway
    implements BrowserMediaGateway, BrowserMediaLifecycleGateway {
  DefaultBrowserMediaGateway({required BrowserMediaClient client})
      : _client = client;

  final BrowserMediaClient _client;
  void Function()? _trackEndedHandler;
  void Function()? _deviceChangeHandler;

  @override
  void setTrackEndedHandler(void Function() handler) {
    _trackEndedHandler = handler;
  }

  @override
  void setDeviceChangeHandler(void Function() handler) {
    _deviceChangeHandler = handler;
    final client = _client;
    if (client is BrowserMediaDeviceChangeClient) {
      (client as BrowserMediaDeviceChangeClient)
          .setDeviceChangeHandler(_handleDeviceChange);
    }
  }

  @override
  Future<BrowserAudioCapabilities> probeCapabilities() {
    return _client.probeCapabilities();
  }

  @override
  Future<BrowserCaptureAttempt> requestMicrophone() async {
    final raw = await _client.requestMicrophone(onEnded: _handleTrackEnded);
    return _map(raw, BrowserCaptureKind.microphone);
  }

  @override
  Future<BrowserCaptureAttempt> requestDisplayAudio() async {
    final raw = await _client.requestDisplayAudio(onEnded: _handleTrackEnded);
    return _map(raw, BrowserCaptureKind.displayAudio);
  }

  void _handleTrackEnded() => _trackEndedHandler?.call();

  void _handleDeviceChange() => _deviceChangeHandler?.call();

  BrowserCaptureAttempt _map(
    BrowserRawCapture raw,
    BrowserCaptureKind kind,
  ) {
    if (raw.status == BrowserRawCaptureStatus.success) {
      if (!raw.hasAudioTrack) {
        return const BrowserCaptureAttempt.noAudioTrack();
      }

      final id = raw.id?.trim();
      final label = raw.label?.trim();
      if (id == null || id.isEmpty) {
        return const BrowserCaptureAttempt.failed('SOURCE ID MISSING');
      }

      return BrowserCaptureAttempt.connected(
        BrowserCaptureSource(
          kind: kind,
          id: id,
          label: label == null || label.isEmpty ? _fallbackLabel(kind) : label,
        ),
      );
    }

    switch ((raw.errorName ?? '').trim().toLowerCase()) {
      case 'notallowederror':
      case 'permissiondeniederror':
      case 'securityerror':
        return const BrowserCaptureAttempt.permissionDenied();
      case 'notsupportederror':
      case 'unsupportederror':
        return const BrowserCaptureAttempt.unsupported();
      case 'notfounderror':
        return const BrowserCaptureAttempt.failed('NO MATCHING AUDIO INPUT FOUND');
      case 'notreadableerror':
        return const BrowserCaptureAttempt.failed('AUDIO INPUT IS NOT READABLE');
      default:
        final name = raw.errorName?.trim();
        return BrowserCaptureAttempt.failed(
          name == null || name.isEmpty ? 'UNKNOWN BROWSER MEDIA ERROR' : name,
        );
    }
  }

  String _fallbackLabel(BrowserCaptureKind kind) {
    return kind == BrowserCaptureKind.microphone
        ? 'BROWSER AUDIO INPUT'
        : 'SHARED DISPLAY AUDIO';
  }
}
