#include <atomic>
#include <cstddef>
#include <cstdint>

#if !defined(__APPLE__)
#error "Issue #3 lock-free atomic acceptance is defined for the initial macOS target only."
#endif

static_assert(
    std::atomic<bool>::is_always_lock_free,
    "Core Audio callback state requires lock-free bool atomics on macOS");
static_assert(
    std::atomic<float>::is_always_lock_free,
    "Mixer callback meters require lock-free float atomics on macOS");
static_assert(
    std::atomic<double>::is_always_lock_free,
    "Capture format telemetry requires lock-free double atomics on macOS");
static_assert(
    std::atomic<std::uint32_t>::is_always_lock_free,
    "Capture state requires lock-free uint32 atomics on macOS");
static_assert(
    std::atomic<std::uint64_t>::is_always_lock_free,
    "Callback and queue counters require lock-free uint64 atomics on macOS");
static_assert(
    std::atomic<std::size_t>::is_always_lock_free,
    "Mixer capture binding requires lock-free size_t atomics on macOS");

int main() {
  return 0;
}
