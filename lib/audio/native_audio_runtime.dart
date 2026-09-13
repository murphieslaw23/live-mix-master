import 'audio_engine_bridge.dart';
import 'audio_permission_state.dart';
import 'native_audio_permission_bindings.dart';

typedef AudioEngineFactory = AudioEngine Function(
  AudioPermissionState permissionState,
);
typedef PermissionPollDelay = Future<void> Function(Duration duration);

class NativeAudioRuntime {
  NativeAudioRuntime({
    required this.permissions,
    required this.engineFactory,
    this.permissionPollInterval = const Duration(milliseconds: 100),
    PermissionPollDelay? pollDelay,
  }) : pollDelay = pollDelay ?? Future<void>.delayed;

  final AudioInputPermissionBindings permissions;
  final AudioEngineFactory engineFactory;
  final Duration permissionPollInterval;
  final PermissionPollDelay pollDelay;

  Future<AudioEngine> prepare() async {
    var permission = permissions.readStatus();
    if (permission == AudioPermissionState.unknown) {
      if (!permissions.request()) {
        throw StateError('Audio input permission request could not be started.');
      }

      permission = permissions.readStatus();
      while (permission == AudioPermissionState.unknown) {
        await pollDelay(permissionPollInterval);
        permission = permissions.readStatus();
      }
    }

    final engine = engineFactory(permission);
    await engine.initialize();
    await engine.refreshInputDevices();
    return engine;
  }
}
