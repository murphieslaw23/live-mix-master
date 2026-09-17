#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum LmmAudioPermissionStatus {
  LMM_AUDIO_PERMISSION_UNKNOWN = 0,
  LMM_AUDIO_PERMISSION_GRANTED = 1,
  LMM_AUDIO_PERMISSION_DENIED = 2,
  LMM_AUDIO_PERMISSION_RESTRICTED = 3,
  LMM_AUDIO_PERMISSION_UNAVAILABLE = 4,
} LmmAudioPermissionStatus;

// Returns the current host audio-input authorization state without prompting.
uint32_t lmm_audio_input_permission_status(void);

// Requests audio-input authorization when the state is not determined.
// Returns true when authorization is already granted or a request was
// successfully initiated. The caller must poll
// lmm_audio_input_permission_status() for the eventual result.
bool lmm_audio_input_permission_request(void);

#ifdef __cplusplus
}
#endif
