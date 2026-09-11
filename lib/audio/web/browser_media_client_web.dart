import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'browser_capture_controller.dart';
import 'browser_media_gateway.dart';

class WebBrowserMediaClient
    implements
        BrowserMediaClient,
        BrowserMediaDeviceChangeClient,
        BrowserMediaDisconnectClient {
  WebBrowserMediaClient();

  web.MediaStream? _activeStream;
  void Function()? _deviceChangeHandler;
  bool _deviceChangeListenerInstalled = false;

  web.MediaStream? get activeStream => _activeStream;

  @override
  Future<BrowserAudioCapabilities> probeCapabilities() async {
    final navigator = web.window.navigator;
    if (!navigator.has('mediaDevices')) {
      return const BrowserAudioCapabilities(
        mediaDevicesAvailable: false,
        microphoneCaptureAvailable: false,
        displayCaptureAvailable: false,
        systemAudioGuaranteed: false,
      );
    }

    final devices = navigator.mediaDevices;
    return BrowserAudioCapabilities(
      mediaDevicesAvailable: true,
      microphoneCaptureAvailable: devices.has('getUserMedia'),
      displayCaptureAvailable: devices.has('getDisplayMedia'),
      systemAudioGuaranteed: false,
    );
  }

  @override
  void setDeviceChangeHandler(void Function() handler) {
    _deviceChangeHandler = handler;
    if (_deviceChangeListenerInstalled) {
      return;
    }

    final navigator = web.window.navigator;
    if (!navigator.has('mediaDevices')) {
      return;
    }

    navigator.mediaDevices.addEventListener(
      'devicechange',
      ((web.Event _) {
        _deviceChangeHandler?.call();
      }).toJS,
    );
    _deviceChangeListenerInstalled = true;
  }

  @override
  void disconnectActiveStream() {
    _stopActiveStream();
  }

  @override
  Future<BrowserRawCapture> requestMicrophone({
    required void Function() onEnded,
  }) async {
    final devices = web.window.navigator.mediaDevices;
    if (!devices.has('getUserMedia')) {
      return const BrowserRawCapture.failure(errorName: 'NotSupportedError');
    }

    return _capture(
      request: () => devices
          .getUserMedia(
            web.MediaStreamConstraints(
              audio: true.toJS,
              video: false.toJS,
            ),
          )
          .toDart,
      onEnded: onEnded,
    );
  }

  @override
  Future<BrowserRawCapture> requestDisplayAudio({
    required void Function() onEnded,
  }) async {
    final devices = web.window.navigator.mediaDevices;
    if (!devices.has('getDisplayMedia')) {
      return const BrowserRawCapture.failure(errorName: 'NotSupportedError');
    }

    return _capture(
      request: () => devices
          .getDisplayMedia(
            web.DisplayMediaStreamOptions(
              audio: true.toJS,
              video: true.toJS,
            ),
          )
          .toDart,
      onEnded: onEnded,
    );
  }

  Future<BrowserRawCapture> _capture({
    required Future<web.MediaStream> Function() request,
    required void Function() onEnded,
  }) async {
    try {
      _stopActiveStream();
      final stream = await request();
      final audioTracks = stream.getAudioTracks().toDart;
      if (audioTracks.isEmpty) {
        _stopStream(stream);
        return BrowserRawCapture.success(
          id: stream.id,
          label: '',
          hasAudioTrack: false,
        );
      }

      final track = audioTracks.first;
      track.addEventListener(
        'ended',
        ((web.Event _) {
          if (identical(_activeStream, stream)) {
            _activeStream = null;
          }
          onEnded();
        }).toJS,
      );
      _activeStream = stream;

      return BrowserRawCapture.success(
        id: track.id.isEmpty ? stream.id : track.id,
        label: track.label,
        hasAudioTrack: true,
      );
    } on Object catch (error) {
      return BrowserRawCapture.failure(errorName: _browserErrorName(error));
    }
  }

  void _stopActiveStream() {
    final stream = _activeStream;
    _activeStream = null;
    if (stream != null) {
      _stopStream(stream);
    }
  }

  void _stopStream(web.MediaStream stream) {
    for (final track in stream.getTracks().toDart) {
      track.stop();
    }
  }

  String _browserErrorName(Object error) {
    try {
      final jsObject = error as JSObject;
      final name = jsObject['name'];
      final dartName = name?.dartify()?.toString().trim();
      if (dartName != null && dartName.isNotEmpty) {
        return dartName;
      }
    } on Object {
      // Fall through to a sanitized string representation.
    }

    final text = error.toString().trim();
    if (text.isEmpty) {
      return 'UnknownError';
    }
    final separator = text.indexOf(':');
    return separator > 0 ? text.substring(0, separator).trim() : text;
  }
}