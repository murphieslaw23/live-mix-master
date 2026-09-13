import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'native_audio_gain_bindings.dart';

typedef _SetTrimNative = Bool Function(Pointer<Utf8>, Float);
typedef _SetTrimDart = bool Function(Pointer<Utf8>, double);
typedef _SetMasterGainNative = Bool Function(Float);
typedef _SetMasterGainDart = bool Function(double);

class FfiNativeAudioGainBindings implements NativeAudioGainBindings {
  FfiNativeAudioGainBindings(DynamicLibrary library)
      : _setTrim = library.lookupFunction<_SetTrimNative, _SetTrimDart>(
          'lmm_set_channel_trim_db',
        ),
        _setMasterGain =
            library.lookupFunction<_SetMasterGainNative, _SetMasterGainDart>(
          'lmm_set_master_gain_db',
        );

  final _SetTrimDart _setTrim;
  final _SetMasterGainDart _setMasterGain;

  @override
  bool setTrim(String channelId, double db) {
    final nativeId = channelId.toNativeUtf8();
    try {
      return _setTrim(nativeId, db);
    } finally {
      calloc.free(nativeId);
    }
  }

  @override
  bool setMasterGain(double db) => _setMasterGain(db);
}
