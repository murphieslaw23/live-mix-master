import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/audio_permission_state.dart';

void main() {
  group('audio permission and device availability vocabulary', () {
    test('permission state models TCC outcomes without device absence', () {
      expect(
        AudioPermissionState.values.map((state) => state.name).toList(),
        <String>['unknown', 'granted', 'denied', 'restricted', 'unavailable'],
      );
      expect(
        AudioPermissionState.values.any((state) => state.name == 'noDevice'),
        isFalse,
      );
    });

    test('device availability models no-device separately from permission', () {
      expect(
        AudioInputAvailability.values.map((state) => state.name).toList(),
        <String>['unknown', 'available', 'noDevice'],
      );
    });

    test('only granted permission is capture-authorized', () {
      expect(AudioPermissionState.granted.canCapture, isTrue);
      for (final state in AudioPermissionState.values.where(
        (state) => state != AudioPermissionState.granted,
      )) {
        expect(state.canCapture, isFalse, reason: '${state.name} must not capture');
      }
    });
  });
}
