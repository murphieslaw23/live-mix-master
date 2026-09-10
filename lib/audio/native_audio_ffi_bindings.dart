import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'native_audio_bindings.dart';

const int _deviceUidCapacity = 256;
const int _deviceNameCapacity = 256;

final class _LmmInputDeviceRecord extends Struct {
  @Uint32()
  external int objectId;

  @Array(_deviceUidCapacity)
  external Array<Uint8> uid;

  @Array(_deviceNameCapacity)
  external Array<Uint8> name;

  @Uint32()
  external int inputChannels;

  @Double()
  external double nominalSampleRate;

  @Uint32()
  external int bufferFrameSize;
}

final class _LmmCaptureStatus extends Struct {
  @Uint32()
  external int state;

  @Double()
  external double sampleRate;

  @Uint32()
  external int bufferFrames;

  @Uint32()
  external int inputChannels;

  @Uint32()
  external int formatFlags;

  @Uint64()
  external int callbackCount;

  @Uint64()
  external int xrunCount;

  @Double()
  external double averageCallbackUs;

  @Double()
  external double maxCallbackUs;
}

final class _LmmChannelMeterSnapshot extends Struct {
  @Float()
  external double peakLeft;

  @Float()
  external double peakRight;

  @Float()
  external double rmsLeft;

  @Float()
  external double rmsRight;

  @Uint8()
  external int clipping;

  @Array(3)
  external Array<Uint8> reserved;
}

final class _LmmMasterMeterSnapshot extends Struct {
  @Float()
  external double truePeakLeft;

  @Float()
  external double truePeakRight;

  @Uint8()
  external int limiterActive;

  @Array(3)
  external Array<Uint8> reserved;
}

typedef _InitNative = Bool Function(Uint32, Uint32);
typedef _InitDart = bool Function(int, int);
typedef _ListInputDevicesNative = IntPtr Function(
  Pointer<_LmmInputDeviceRecord>,
  IntPtr,
);
typedef _ListInputDevicesDart = int Function(
  Pointer<_LmmInputDeviceRecord>,
  int,
);
typedef _ChannelIdBoolNative = Bool Function(Pointer<Utf8>);
typedef _ChannelIdBoolDart = bool Function(Pointer<Utf8>);
typedef _SetFaderNative = Bool Function(Pointer<Utf8>, Float);
typedef _SetFaderDart = bool Function(Pointer<Utf8>, double);
typedef _SetFlagNative = Bool Function(Pointer<Utf8>, Bool);
typedef _SetFlagDart = bool Function(Pointer<Utf8>, bool);
typedef _CaptureStopNative = Void Function();
typedef _CaptureStopDart = void Function();
typedef _CaptureStatusNative = Bool Function(Pointer<_LmmCaptureStatus>);
typedef _CaptureStatusDart = bool Function(Pointer<_LmmCaptureStatus>);
typedef _ChannelMeterNative = Bool Function(
  Pointer<Utf8>,
  Pointer<_LmmChannelMeterSnapshot>,
);
typedef _ChannelMeterDart = bool Function(
  Pointer<Utf8>,
  Pointer<_LmmChannelMeterSnapshot>,
);
typedef _MasterMeterNative = Bool Function(Pointer<_LmmMasterMeterSnapshot>);
typedef _MasterMeterDart = bool Function(Pointer<_LmmMasterMeterSnapshot>);

/// DynamicLibrary-backed implementation of the stable LiveMixMaster C ABI.
///
/// All methods are synchronous non-real-time control/status calls. The native
/// capture callback never invokes Dart and no callback pointer is registered.
class FfiNativeAudioBindings implements NativeAudioBindings {
  FfiNativeAudioBindings(DynamicLibrary library)
      : _initialize = library.lookupFunction<_InitNative, _InitDart>('lmm_init'),
        _listInputDevices = library.lookupFunction<
            _ListInputDevicesNative,
            _ListInputDevicesDart>('lmm_list_input_devices'),
        _addChannel = library.lookupFunction<_ChannelIdBoolNative,
            _ChannelIdBoolDart>('lmm_add_channel'),
        _removeChannel = library.lookupFunction<_ChannelIdBoolNative,
            _ChannelIdBoolDart>('lmm_remove_channel'),
        _setFader = library.lookupFunction<_SetFaderNative, _SetFaderDart>(
          'lmm_set_channel_fader',
        ),
        _setMuted = library.lookupFunction<_SetFlagNative, _SetFlagDart>(
          'lmm_set_channel_muted',
        ),
        _setSolo = library.lookupFunction<_SetFlagNative, _SetFlagDart>(
          'lmm_set_channel_solo',
        ),
        _bindCaptureChannel = library.lookupFunction<_ChannelIdBoolNative,
            _ChannelIdBoolDart>('lmm_bind_capture_channel'),
        _captureStart = library.lookupFunction<_ChannelIdBoolNative,
            _ChannelIdBoolDart>('lmm_capture_start'),
        _captureStop = library.lookupFunction<_CaptureStopNative,
            _CaptureStopDart>('lmm_capture_stop'),
        _captureGetStatus = library.lookupFunction<_CaptureStatusNative,
            _CaptureStatusDart>('lmm_capture_get_status'),
        _getChannelMeter = library.lookupFunction<_ChannelMeterNative,
            _ChannelMeterDart>('lmm_get_channel_meter'),
        _getMasterMeter = library.lookupFunction<_MasterMeterNative,
            _MasterMeterDart>('lmm_get_master_meter');

  final _InitDart _initialize;
  final _ListInputDevicesDart _listInputDevices;
  final _ChannelIdBoolDart _addChannel;
  final _ChannelIdBoolDart _removeChannel;
  final _SetFaderDart _setFader;
  final _SetFlagDart _setMuted;
  final _SetFlagDart _setSolo;
  final _ChannelIdBoolDart _bindCaptureChannel;
  final _ChannelIdBoolDart _captureStart;
  final _CaptureStopDart _captureStop;
  final _CaptureStatusDart _captureGetStatus;
  final _ChannelMeterDart _getChannelMeter;
  final _MasterMeterDart _getMasterMeter;

  @override
  bool initialize(int sampleRate, int framesPerBuffer) =>
      _initialize(sampleRate, framesPerBuffer);

  @override
  List<NativeInputDevice> listInputDevices() {
    final count = _listInputDevices(nullptr, 0);
    if (count <= 0) return const <NativeInputDevice>[];

    final records = calloc<_LmmInputDeviceRecord>(count);
    try {
      final written = _listInputDevices(records, count);
      return List<NativeInputDevice>.unmodifiable(
        List<NativeInputDevice>.generate(written, (index) {
          final record = records.elementAt(index).ref;
          return NativeInputDevice(
            objectId: record.objectId,
            uid: _decodeFixedUtf8(record.uid, _deviceUidCapacity),
            name: _decodeFixedUtf8(record.name, _deviceNameCapacity),
            inputChannels: record.inputChannels,
            nominalSampleRate: record.nominalSampleRate,
            bufferFrames: record.bufferFrameSize,
          );
        }),
      );
    } finally {
      calloc.free(records);
    }
  }

  @override
  bool addChannel(String id) => _withUtf8(id, _addChannel);

  @override
  bool removeChannel(String id) => _withUtf8(id, _removeChannel);

  @override
  bool setFader(String id, double value) {
    final nativeId = id.toNativeUtf8();
    try {
      return _setFader(nativeId, value);
    } finally {
      calloc.free(nativeId);
    }
  }

  @override
  bool setMuted(String id, bool value) {
    final nativeId = id.toNativeUtf8();
    try {
      return _setMuted(nativeId, value);
    } finally {
      calloc.free(nativeId);
    }
  }

  @override
  bool setSolo(String id, bool value) {
    final nativeId = id.toNativeUtf8();
    try {
      return _setSolo(nativeId, value);
    } finally {
      calloc.free(nativeId);
    }
  }

  @override
  bool bindCaptureChannel(String id) => _withUtf8(id, _bindCaptureChannel);

  @override
  bool captureStart(String uid) => _withUtf8(uid, _captureStart);

  @override
  void captureStop() => _captureStop();

  @override
  NativeCaptureStatus captureStatus() {
    final out = calloc<_LmmCaptureStatus>();
    try {
      if (!_captureGetStatus(out)) {
        throw StateError('Native capture status read failed.');
      }
      final value = out.ref;
      return NativeCaptureStatus(
        state: _captureState(value.state),
        sampleRate: value.sampleRate,
        bufferFrames: value.bufferFrames,
        inputChannels: value.inputChannels,
        formatFlags: value.formatFlags,
        callbackCount: value.callbackCount,
        xrunCount: value.xrunCount,
        averageCallbackUs: value.averageCallbackUs,
        maxCallbackUs: value.maxCallbackUs,
      );
    } finally {
      calloc.free(out);
    }
  }

  @override
  NativeChannelMeter? channelMeter(String id) {
    final nativeId = id.toNativeUtf8();
    final out = calloc<_LmmChannelMeterSnapshot>();
    try {
      if (!_getChannelMeter(nativeId, out)) return null;
      final value = out.ref;
      return NativeChannelMeter(
        peakLeft: value.peakLeft,
        peakRight: value.peakRight,
        rmsLeft: value.rmsLeft,
        rmsRight: value.rmsRight,
        clipping: value.clipping != 0,
      );
    } finally {
      calloc.free(out);
      calloc.free(nativeId);
    }
  }

  @override
  NativeMasterMeter? masterMeter() {
    final out = calloc<_LmmMasterMeterSnapshot>();
    try {
      if (!_getMasterMeter(out)) return null;
      final value = out.ref;
      return NativeMasterMeter(
        truePeakLeft: value.truePeakLeft,
        truePeakRight: value.truePeakRight,
        limiterActive: value.limiterActive != 0,
      );
    } finally {
      calloc.free(out);
    }
  }

  static bool _withUtf8(String value, _ChannelIdBoolDart function) {
    final nativeValue = value.toNativeUtf8();
    try {
      return function(nativeValue);
    } finally {
      calloc.free(nativeValue);
    }
  }

  static String _decodeFixedUtf8(Array<Uint8> source, int capacity) {
    final bytes = <int>[];
    for (var index = 0; index < capacity; index += 1) {
      final byte = source[index];
      if (byte == 0) break;
      bytes.add(byte);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static NativeCaptureState _captureState(int raw) => switch (raw) {
        0 => NativeCaptureState.idle,
        1 => NativeCaptureState.starting,
        2 => NativeCaptureState.running,
        3 => NativeCaptureState.deviceRemoved,
        4 => NativeCaptureState.formatChanged,
        5 => NativeCaptureState.failed,
        _ => throw StateError('Unknown native capture state: $raw'),
      };
}
