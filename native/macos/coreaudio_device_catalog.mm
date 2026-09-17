#include "lmm_device_catalog.h"

#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <vector>

namespace {

AudioObjectPropertyAddress addressFor(
    AudioObjectPropertySelector selector,
    AudioObjectPropertyScope scope = kAudioObjectPropertyScopeGlobal) {
  return AudioObjectPropertyAddress{
      selector,
      scope,
      kAudioObjectPropertyElementMain,
  };
}

template <typename T>
bool readScalar(
    AudioObjectID objectId,
    AudioObjectPropertySelector selector,
    AudioObjectPropertyScope scope,
    T& outValue) {
  const auto address = addressFor(selector, scope);
  if (!AudioObjectHasProperty(objectId, &address)) return false;

  UInt32 size = static_cast<UInt32>(sizeof(T));
  return AudioObjectGetPropertyData(
             objectId,
             &address,
             0,
             nullptr,
             &size,
             &outValue) == noErr &&
      size == sizeof(T);
}

bool copyStringProperty(
    AudioObjectID objectId,
    AudioObjectPropertySelector selector,
    char* output,
    std::size_t outputCapacity) {
  if (!output || outputCapacity == 0) return false;
  output[0] = '\0';

  const auto address = addressFor(selector);
  if (!AudioObjectHasProperty(objectId, &address)) return false;

  CFStringRef value = nullptr;
  UInt32 size = static_cast<UInt32>(sizeof(value));
  const OSStatus status = AudioObjectGetPropertyData(
      objectId,
      &address,
      0,
      nullptr,
      &size,
      &value);
  if (status != noErr || value == nullptr) return false;

  const bool copied = CFStringGetCString(
      value,
      output,
      static_cast<CFIndex>(outputCapacity),
      kCFStringEncodingUTF8);
  CFRelease(value);
  if (!copied) output[0] = '\0';
  output[outputCapacity - 1] = '\0';
  return copied;
}

std::uint32_t inputChannelCount(AudioObjectID deviceId) {
  const auto address = addressFor(
      kAudioDevicePropertyStreamConfiguration,
      kAudioDevicePropertyScopeInput);
  if (!AudioObjectHasProperty(deviceId, &address)) return 0;

  UInt32 size = 0;
  if (AudioObjectGetPropertyDataSize(
          deviceId,
          &address,
          0,
          nullptr,
          &size) != noErr ||
      size < sizeof(AudioBufferList)) {
    return 0;
  }

  std::vector<std::uint8_t> storage(size);
  auto* bufferList = reinterpret_cast<AudioBufferList*>(storage.data());
  if (AudioObjectGetPropertyData(
          deviceId,
          &address,
          0,
          nullptr,
          &size,
          bufferList) != noErr) {
    return 0;
  }

  std::uint32_t channels = 0;
  for (UInt32 index = 0; index < bufferList->mNumberBuffers; ++index) {
    channels += bufferList->mBuffers[index].mNumberChannels;
  }
  return channels;
}

std::vector<AudioObjectID> allAudioDevices() {
  const auto address = addressFor(kAudioHardwarePropertyDevices);
  UInt32 size = 0;
  if (AudioObjectGetPropertyDataSize(
          kAudioObjectSystemObject,
          &address,
          0,
          nullptr,
          &size) != noErr ||
      size == 0 ||
      size % sizeof(AudioObjectID) != 0) {
    return {};
  }

  std::vector<AudioObjectID> devices(size / sizeof(AudioObjectID));
  if (AudioObjectGetPropertyData(
          kAudioObjectSystemObject,
          &address,
          0,
          nullptr,
          &size,
          devices.data()) != noErr) {
    return {};
  }
  devices.resize(size / sizeof(AudioObjectID));
  return devices;
}

bool buildInputDeviceRecord(AudioObjectID deviceId, LmmInputDeviceRecord& record) {
  record = {};
  const std::uint32_t channels = inputChannelCount(deviceId);
  if (channels == 0) return false;

  if (!copyStringProperty(
          deviceId,
          kAudioDevicePropertyDeviceUID,
          record.uid,
          LMM_DEVICE_UID_CAPACITY) ||
      record.uid[0] == '\0') {
    return false;
  }

  copyStringProperty(
      deviceId,
      kAudioObjectPropertyName,
      record.name,
      LMM_DEVICE_NAME_CAPACITY);

  Float64 nominalSampleRate = 0.0;
  UInt32 bufferFrameSize = 0;
  if (!readScalar(
          deviceId,
          kAudioDevicePropertyNominalSampleRate,
          kAudioObjectPropertyScopeGlobal,
          nominalSampleRate) ||
      nominalSampleRate <= 0.0) {
    return false;
  }
  if (!readScalar(
          deviceId,
          kAudioDevicePropertyBufferFrameSize,
          kAudioObjectPropertyScopeGlobal,
          bufferFrameSize) ||
      bufferFrameSize == 0) {
    return false;
  }

  record.object_id = static_cast<std::uint32_t>(deviceId);
  record.input_channels = channels;
  record.nominal_sample_rate = nominalSampleRate;
  record.buffer_frame_size = bufferFrameSize;
  return record.object_id != 0;
}

std::vector<LmmInputDeviceRecord> collectInputDevices() {
  const auto devices = allAudioDevices();
  std::vector<LmmInputDeviceRecord> records;
  records.reserve(devices.size());

  for (const auto deviceId : devices) {
    LmmInputDeviceRecord record{};
    if (buildInputDeviceRecord(deviceId, record)) {
      records.push_back(record);
    }
  }
  return records;
}

}  // namespace

extern "C" std::size_t lmm_list_input_devices(
    LmmInputDeviceRecord* outRecords,
    std::size_t capacity) {
  const auto records = collectInputDevices();
  if (outRecords == nullptr || capacity == 0) return records.size();

  const std::size_t written = std::min(capacity, records.size());
  for (std::size_t index = 0; index < written; ++index) {
    outRecords[index] = records[index];
  }
  return written;
}
