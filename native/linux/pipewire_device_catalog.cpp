#include "lmm_device_catalog.h"

#include <pipewire/pipewire.h>
#include <spa/utils/dict.h>

#include <algorithm>
#include <array>
#include <charconv>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <string_view>
#include <vector>

namespace {

constexpr std::string_view kAudioSourceClass = "Audio/Source";
constexpr std::string_view kAudioSinkClass = "Audio/Sink";
constexpr std::string_view kSourceUidPrefix = "pipewire:source:";
constexpr std::string_view kSinkUidPrefix = "pipewire:sink:";
constexpr std::uint32_t kDefaultSampleRate = 48000;
constexpr std::uint32_t kDefaultBufferFrames = 256;
constexpr std::uint32_t kDefaultChannels = 2;

void ensurePipeWireInitialized() {
  static std::once_flag initialized;
  std::call_once(initialized, [] { pw_init(nullptr, nullptr); });
}

bool copyString(std::string_view source, char* destination, std::size_t capacity) {
  if (!destination || capacity == 0 || source.empty()) return false;
  const auto length = std::min(source.size(), capacity - 1);
  std::memcpy(destination, source.data(), length);
  destination[length] = '\0';
  return true;
}

std::uint32_t parseUnsigned(const char* value, std::uint32_t fallback) {
  if (!value || *value == '\0') return fallback;
  std::uint32_t parsed = 0;
  const auto* begin = value;
  const auto* end = value + std::strlen(value);
  const auto [cursor, error] = std::from_chars(begin, end, parsed);
  return error == std::errc{} && cursor == end && parsed > 0 ? parsed : fallback;
}

std::uint32_t parseBufferFrames(const char* latency) {
  if (!latency || *latency == '\0') return kDefaultBufferFrames;
  const auto* begin = latency;
  const auto* slash = std::strchr(begin, '/');
  if (!slash) return kDefaultBufferFrames;
  std::uint32_t frames = 0;
  const auto [cursor, error] = std::from_chars(begin, slash, frames);
  return error == std::errc{} && cursor == slash && frames > 0 ? frames : kDefaultBufferFrames;
}

struct CatalogQuery {
  pw_main_loop* loop = nullptr;
  pw_context* context = nullptr;
  pw_core* core = nullptr;
  pw_registry* registry = nullptr;
  spa_hook coreListener{};
  spa_hook registryListener{};
  int syncSequence = -1;
  std::vector<LmmInputDeviceRecord> records;
};

void onRegistryGlobal(
    void* data,
    std::uint32_t id,
    std::uint32_t,
    const char* type,
    std::uint32_t,
    const spa_dict* properties) {
  auto& query = *static_cast<CatalogQuery*>(data);
  if (!type || std::strcmp(type, PW_TYPE_INTERFACE_Node) != 0 || !properties) return;

  const char* mediaClass = spa_dict_lookup(properties, PW_KEY_MEDIA_CLASS);
  const char* nodeName = spa_dict_lookup(properties, PW_KEY_NODE_NAME);
  if (!mediaClass || !nodeName || *nodeName == '\0') return;

  const std::string_view mediaClassView(mediaClass);
  const bool isSource = mediaClassView == kAudioSourceClass;
  const bool isSink = mediaClassView == kAudioSinkClass;
  if (!isSource && !isSink) return;

  const char* displayName = spa_dict_lookup(properties, PW_KEY_NODE_DESCRIPTION);
  if (!displayName || *displayName == '\0') displayName = nodeName;

  LmmInputDeviceRecord record{};
  record.object_id = id == 0 ? 1 : id;
  const auto prefix = isSource ? kSourceUidPrefix : kSinkUidPrefix;
  const std::string uid = std::string(prefix) + nodeName;
  if (!copyString(uid, record.uid, LMM_DEVICE_UID_CAPACITY) ||
      !copyString(displayName, record.name, LMM_DEVICE_NAME_CAPACITY)) {
    return;
  }

  record.input_channels = parseUnsigned(
      spa_dict_lookup(properties, PW_KEY_AUDIO_CHANNELS),
      kDefaultChannels);
  record.nominal_sample_rate = static_cast<double>(parseUnsigned(
      spa_dict_lookup(properties, PW_KEY_AUDIO_RATE),
      kDefaultSampleRate));
  record.buffer_frame_size = parseBufferFrames(
      spa_dict_lookup(properties, PW_KEY_NODE_LATENCY));
  query.records.push_back(record);
}

void onCoreDone(void* data, std::uint32_t id, int sequence) {
  auto& query = *static_cast<CatalogQuery*>(data);
  if (id == PW_ID_CORE && sequence == query.syncSequence && query.loop) {
    pw_main_loop_quit(query.loop);
  }
}

void onCoreError(void* data, std::uint32_t, int, int, const char*) {
  auto& query = *static_cast<CatalogQuery*>(data);
  if (query.loop) pw_main_loop_quit(query.loop);
}

const pw_registry_events kRegistryEvents = {
    PW_VERSION_REGISTRY_EVENTS,
    .global = onRegistryGlobal,
};

const pw_core_events kCoreEvents = {
    PW_VERSION_CORE_EVENTS,
    .done = onCoreDone,
    .error = onCoreError,
};

void destroyCatalogQuery(CatalogQuery& query) {
  spa_hook_remove(&query.registryListener);
  spa_hook_remove(&query.coreListener);
  if (query.core) pw_core_disconnect(query.core);
  if (query.context) pw_context_destroy(query.context);
  if (query.loop) pw_main_loop_destroy(query.loop);
}

std::vector<LmmInputDeviceRecord> collectInputDevices() {
  ensurePipeWireInitialized();

  CatalogQuery query;
  query.loop = pw_main_loop_new(nullptr);
  if (!query.loop) return {};
  query.context = pw_context_new(pw_main_loop_get_loop(query.loop), nullptr, 0);
  if (!query.context) {
    destroyCatalogQuery(query);
    return {};
  }
  query.core = pw_context_connect(query.context, nullptr, 0);
  if (!query.core) {
    destroyCatalogQuery(query);
    return {};
  }
  query.registry = pw_core_get_registry(query.core, PW_VERSION_REGISTRY, 0);
  if (!query.registry) {
    destroyCatalogQuery(query);
    return {};
  }

  pw_core_add_listener(query.core, &query.coreListener, &kCoreEvents, &query);
  pw_registry_add_listener(query.registry, &query.registryListener, &kRegistryEvents, &query);
  query.syncSequence = pw_core_sync(query.core, PW_ID_CORE, 0);
  if (query.syncSequence >= 0) {
    (void)pw_main_loop_run(query.loop);
  }

  auto records = std::move(query.records);
  destroyCatalogQuery(query);
  std::sort(records.begin(), records.end(), [](const auto& left, const auto& right) {
    return std::strcmp(left.uid, right.uid) < 0;
  });
  return records;
}

}  // namespace

bool lmm_linux_pipewire_session_available() {
  ensurePipeWireInitialized();
  pw_main_loop* loop = pw_main_loop_new(nullptr);
  if (!loop) return false;
  pw_context* context = pw_context_new(pw_main_loop_get_loop(loop), nullptr, 0);
  if (!context) {
    pw_main_loop_destroy(loop);
    return false;
  }
  pw_core* core = pw_context_connect(context, nullptr, 0);
  const bool connected = core != nullptr;
  if (core) pw_core_disconnect(core);
  pw_context_destroy(context);
  pw_main_loop_destroy(loop);
  return connected;
}

extern "C" std::size_t lmm_list_input_devices(
    LmmInputDeviceRecord* outRecords,
    std::size_t capacity) {
  const auto records = collectInputDevices();
  if (!outRecords || capacity == 0) return records.size();

  const std::size_t written = std::min(capacity, records.size());
  for (std::size_t index = 0; index < written; ++index) {
    outRecords[index] = records[index];
  }
  return written;
}
