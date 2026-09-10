import 'dart:ffi';

import 'audio_permission_state.dart';

typedef _PermissionStatusNative = Uint32 Function();
typedef _PermissionStatusDart = int Function();
typedef _PermissionRequestNative = Bool Function();
typedef _PermissionRequestDart = bool Function();

/// Narrow FFI bridge for host audio-input authorization.
///
/// Status reads are side-effect free. [request] is the only call that may ask
/// the host OS to present its microphone consent UI.
class FfiAudioPermissionBindings {
  FfiAudioPermissionBindings(DynamicLibrary library)
      : _status = library.lookupFunction<
            _PermissionStatusNative,
            _PermissionStatusDart>('lmm_audio_input_permission_status'),
        _request = library.lookupFunction<
            _PermissionRequestNative,
            _PermissionRequestDart>('lmm_audio_input_permission_request');

  final _PermissionStatusDart _status;
  final _PermissionRequestDart _request;

  AudioPermissionState get status => mapStatus(_status());

  bool request() => _request();

  static AudioPermissionState mapStatus(int raw) => switch (raw) {
        0 => AudioPermissionState.unknown,
        1 => AudioPermissionState.granted,
        2 => AudioPermissionState.denied,
        3 => AudioPermissionState.restricted,
        4 => AudioPermissionState.unavailable,
        _ => throw StateError('Unknown native audio permission state: $raw'),
      };
}
