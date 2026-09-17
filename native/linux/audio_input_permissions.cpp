#include "lmm_permissions.h"

// PipeWire session policy owns microphone and portal authorization on Linux.
// This ABI has no prompt equivalent to macOS AVFoundation: a reachable session
// means the native host may enumerate/capture, while node-specific denial is
// reported by the capture lifecycle after a selected route is requested.
bool lmm_linux_pipewire_session_available();

extern "C" uint32_t lmm_audio_input_permission_status(void) {
  return lmm_linux_pipewire_session_available()
      ? LMM_AUDIO_PERMISSION_GRANTED
      : LMM_AUDIO_PERMISSION_UNAVAILABLE;
}

extern "C" bool lmm_audio_input_permission_request(void) {
  return lmm_linux_pipewire_session_available();
}
