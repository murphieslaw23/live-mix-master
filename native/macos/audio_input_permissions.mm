#include "lmm_permissions.h"

#import <AVFoundation/AVFoundation.h>

namespace {

uint32_t mapAuthorizationStatus(AVAuthorizationStatus status) {
  switch (status) {
    case AVAuthorizationStatusNotDetermined:
      return LMM_AUDIO_PERMISSION_UNKNOWN;
    case AVAuthorizationStatusAuthorized:
      return LMM_AUDIO_PERMISSION_GRANTED;
    case AVAuthorizationStatusDenied:
      return LMM_AUDIO_PERMISSION_DENIED;
    case AVAuthorizationStatusRestricted:
      return LMM_AUDIO_PERMISSION_RESTRICTED;
  }
  return LMM_AUDIO_PERMISSION_UNAVAILABLE;
}

}  // namespace

extern "C" uint32_t lmm_audio_input_permission_status(void) {
  @autoreleasepool {
    return mapAuthorizationStatus(
        [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio]);
  }
}

extern "C" bool lmm_audio_input_permission_request(void) {
  @autoreleasepool {
    const AVAuthorizationStatus status =
        [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];

    switch (status) {
      case AVAuthorizationStatusAuthorized:
        return true;
      case AVAuthorizationStatusDenied:
      case AVAuthorizationStatusRestricted:
        return false;
      case AVAuthorizationStatusNotDetermined:
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio
                                 completionHandler:^(BOOL granted) {
                                   (void)granted;
                                 }];
        return true;
    }

    return false;
  }
}
