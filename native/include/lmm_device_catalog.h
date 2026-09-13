#pragma once

#include <cstddef>
#include <cstdint>

extern "C" {

constexpr std::size_t LMM_DEVICE_UID_CAPACITY = 256;
constexpr std::size_t LMM_DEVICE_NAME_CAPACITY = 256;

struct LmmInputDeviceRecord {
  std::uint32_t object_id;
  char uid[LMM_DEVICE_UID_CAPACITY];
  char name[LMM_DEVICE_NAME_CAPACITY];
  std::uint32_t input_channels;
  double nominal_sample_rate;
  std::uint32_t buffer_frame_size;
};

// Count query: out_records == nullptr or capacity == 0 returns the number of
// currently eligible Core Audio input endpoints.
//
// Fill query: writes at most `capacity` records and returns the number written.
// Device selection in later tasks consumes `uid`; `name` is display-only.
std::size_t lmm_list_input_devices(
    LmmInputDeviceRecord* out_records,
    std::size_t capacity);

}  // extern "C"
