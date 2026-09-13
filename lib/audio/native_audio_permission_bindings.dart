import 'dart:ffi';

import 'audio_permission_state.dart';

abstract interface class AudioInputPermissionBindings {
  AudioPermissionState readStatus();
  bool request();
}

typedef _PermissionStatusNative = Uint32 Function();
typedef _PermissionStatusDart = int Function();
typedef _PermissionRequestNative = Bool Function();
typedef _PermissionRequestDart = bool Function();

class FfiAudioInputPermissionBindings implements AudioInputPermissionBindings {
  FfiAudioInputPermissionBindings(DynamicLibrary library)
      : _readStatus = library.lookupFunction<
            _PermissionStatusNative,
            _PermissionStatusDart>('lmm_audio_input_permission_status'),
        _request = library.lookupFunction<
            _PermissionRequestNative,
            _PermissionRequestDart>('lmm_audio_input_permission_request');

  final _PermissionStatusDart _readStatus;
  final _PermissionRequestDart _request;

  @override
  AudioPermissionState readStatus() => switch (_readStatus()) {
        0 => AudioPermissionState.unknown,
        1 => AudioPermissionState.granted,
        2 => AudioPermissionState.denied,
        3 => AudioPermissionState.restricted,
        4 => AudioPermissionState.unavailable,
        final value => throw StateError(
            'Unknown native audio permission status: $value',
          ),
      };

  @override
  bool request() => _request();
}
