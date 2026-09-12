enum AudioPermissionState {
  unknown,
  granted,
  denied,
  restricted,
  unavailable;

  bool get canCapture => this == AudioPermissionState.granted;
}

enum AudioInputAvailability {
  unknown,
  available,
  noDevice,
}
