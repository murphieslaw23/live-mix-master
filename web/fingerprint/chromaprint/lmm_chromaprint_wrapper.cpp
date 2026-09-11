#include <cstdint>

#include <emscripten/emscripten.h>

#include "chromaprint.h"

extern "C" {

EMSCRIPTEN_KEEPALIVE
const char* lmm_chromaprint_version() {
  return chromaprint_get_version();
}

EMSCRIPTEN_KEEPALIVE
char* lmm_chromaprint_fingerprint(
    const int16_t* pcm,
    int sample_count,
    int sample_rate,
    int channels) {
  if (pcm == nullptr || sample_count <= 0 || sample_rate <= 0 ||
      (channels != 1 && channels != 2)) {
    return nullptr;
  }

  ChromaprintContext* context =
      chromaprint_new(CHROMAPRINT_ALGORITHM_DEFAULT);
  if (context == nullptr) {
    return nullptr;
  }

  char* fingerprint = nullptr;
  const bool ok =
      chromaprint_start(context, sample_rate, channels) == 1 &&
      chromaprint_feed(context, pcm, sample_count) == 1 &&
      chromaprint_finish(context) == 1 &&
      chromaprint_get_fingerprint(context, &fingerprint) == 1 &&
      fingerprint != nullptr;

  chromaprint_free(context);

  if (!ok) {
    if (fingerprint != nullptr) {
      chromaprint_dealloc(fingerprint);
    }
    return nullptr;
  }

  return fingerprint;
}

EMSCRIPTEN_KEEPALIVE
void lmm_chromaprint_free(void* pointer) {
  if (pointer != nullptr) {
    chromaprint_dealloc(pointer);
  }
}

}  // extern "C"
