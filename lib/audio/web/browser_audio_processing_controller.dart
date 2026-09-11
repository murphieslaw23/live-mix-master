import 'browser_capture_controller.dart';
import 'browser_mixer_controller.dart';

enum BrowserAudioProcessingStatus {
  idle,
  starting,
  active,
  unsupported,
  error,
}

enum BrowserAudioProcessingAttemptStatus {
  started,
  unsupported,
  failed,
}

class BrowserAudioProcessingAttempt {
  const BrowserAudioProcessingAttempt._({
    required this.status,
    this.message,
  });

  const BrowserAudioProcessingAttempt.started()
      : this._(status: BrowserAudioProcessingAttemptStatus.started);

  const BrowserAudioProcessingAttempt.unsupported([String? message])
      : this._(
          status: BrowserAudioProcessingAttemptStatus.unsupported,
          message: message,
        );

  const BrowserAudioProcessingAttempt.failed([String? message])
      : this._(
          status: BrowserAudioProcessingAttemptStatus.failed,
          message: message,
        );

  final BrowserAudioProcessingAttemptStatus status;
  final String? message;
}

abstract interface class BrowserAudioProcessingGateway {
  Future<BrowserAudioProcessingAttempt> start(BrowserCaptureSource source);

  Future<void> stop();
}

class BrowserAudioProcessingState {
  const BrowserAudioProcessingState({
    required this.status,
    required this.message,
    this.source,
  });

  const BrowserAudioProcessingState.idle()
      : status = BrowserAudioProcessingStatus.idle,
        message = 'WEB AUDIO PROCESSING IDLE',
        source = null;

  final BrowserAudioProcessingStatus status;
  final String message;
  final BrowserCaptureSource? source;
}

class BrowserAudioProcessingController {
  BrowserAudioProcessingController({required BrowserAudioProcessingGateway gateway})
      : _gateway = gateway;

  final BrowserAudioProcessingGateway _gateway;
  BrowserAudioProcessingState _state = const BrowserAudioProcessingState.idle();

  BrowserAudioProcessingState get state => _state;

  Future<void> startForSource(BrowserCaptureSource source) async {
    _state = BrowserAudioProcessingState(
      status: BrowserAudioProcessingStatus.starting,
      message: 'STARTING AUDIOWORKLET — ${source.label}',
      source: source,
    );

    try {
      final attempt = await _gateway.start(source);
      switch (attempt.status) {
        case BrowserAudioProcessingAttemptStatus.started:
          _state = BrowserAudioProcessingState(
            status: BrowserAudioProcessingStatus.active,
            message: 'AUDIOWORKLET ACTIVE — ${source.label}',
            source: source,
          );
        case BrowserAudioProcessingAttemptStatus.unsupported:
          _state = BrowserAudioProcessingState(
            status: BrowserAudioProcessingStatus.unsupported,
            message: _messageOr(
              attempt.message,
              'AUDIOWORKLET NOT AVAILABLE — SECURE BROWSER CONTEXT REQUIRED',
            ),
          );
        case BrowserAudioProcessingAttemptStatus.failed:
          _state = BrowserAudioProcessingState(
            status: BrowserAudioProcessingStatus.error,
            message: _messageOr(attempt.message, 'AUDIOWORKLET START FAILED'),
          );
      }
    } on Object catch (error) {
      _state = BrowserAudioProcessingState(
        status: BrowserAudioProcessingStatus.error,
        message: 'AUDIOWORKLET START FAILED — ${_sanitize(error)}',
      );
    }
  }

  Future<void> stop() async {
    try {
      await _gateway.stop();
    } finally {
      _state = const BrowserAudioProcessingState.idle();
    }
  }

  String _messageOr(String? message, String fallback) {
    final value = message?.trim();
    return value == null || value.isEmpty ? fallback : value;
  }

  String _sanitize(Object error) {
    final compact = error
        .toString()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(
          RegExp(r'(?i)(token|password|authorization)=?[^ ,;]+'),
          r'$1=[REDACTED]',
        )
        .trim();
    return compact.isEmpty ? 'UNKNOWN ERROR' : compact;
  }
}

class BrowserAudioRuntimeCoordinator {
  BrowserAudioRuntimeCoordinator({
    required BrowserCaptureController captureController,
    required BrowserAudioProcessingController processingController,
    required BrowserMixerController mixerController,
  })  : _captureController = captureController,
        _processingController = processingController,
        _mixerController = mixerController {
    _captureController.addListener(_handleCaptureState);
  }

  final BrowserCaptureController _captureController;
  final BrowserAudioProcessingController _processingController;
  final BrowserMixerController _mixerController;
  Future<void> _transition = Future<void>.value();
  bool _disposed = false;

  Future<void> synchronize() => _transition;

  void _handleCaptureState(BrowserCaptureState state) {
    if (_disposed) {
      return;
    }

    if (state.status == BrowserCaptureStatus.active && state.source != null) {
      final source = state.source!;
      _transition = _transition.then((_) async {
        await _mixerController.detach();
        await _processingController.startForSource(source);
        if (_processingController.state.status ==
            BrowserAudioProcessingStatus.active) {
          await _mixerController.attach(source.id);
        }
      });
      return;
    }

    switch (state.status) {
      case BrowserCaptureStatus.reconnectRequired:
      case BrowserCaptureStatus.permissionDenied:
      case BrowserCaptureStatus.noAudioTrack:
      case BrowserCaptureStatus.unsupported:
      case BrowserCaptureStatus.error:
        _transition = _transition.then((_) async {
          await _mixerController.detach();
          await _processingController.stop();
        });
      case BrowserCaptureStatus.idle:
      case BrowserCaptureStatus.permissionRequired:
      case BrowserCaptureStatus.requesting:
      case BrowserCaptureStatus.active:
      case BrowserCaptureStatus.deviceInventoryChanged:
        break;
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _captureController.removeListener(_handleCaptureState);
    await _transition;
    await _mixerController.detach();
    await _processingController.stop();
  }
}
