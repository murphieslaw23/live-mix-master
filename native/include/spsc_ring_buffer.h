#pragma once

#include <array>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <type_traits>

namespace lmm {

template <typename T, std::size_t Capacity>
class SpscRingBuffer {
  static_assert(Capacity > 0, "SpscRingBuffer capacity must be greater than zero");
  static_assert(std::is_default_constructible_v<T>, "SpscRingBuffer storage requires a default-constructible value type");

 public:
  bool tryPush(const T& value) noexcept(std::is_nothrow_copy_assignable_v<T>) {
    const std::size_t head = head_.load(std::memory_order_relaxed);
    const std::size_t tail = tail_.load(std::memory_order_acquire);
    if (head - tail >= Capacity) {
      rejectedWrites_.fetch_add(1, std::memory_order_relaxed);
      return false;
    }

    storage_[head % Capacity] = value;
    head_.store(head + 1, std::memory_order_release);
    return true;
  }

  bool tryPop(T& out) noexcept(std::is_nothrow_copy_assignable_v<T>) {
    const std::size_t tail = tail_.load(std::memory_order_relaxed);
    const std::size_t head = head_.load(std::memory_order_acquire);
    if (tail == head) return false;

    out = storage_[tail % Capacity];
    tail_.store(tail + 1, std::memory_order_release);
    return true;
  }

  std::size_t size() const noexcept {
    const std::size_t head = head_.load(std::memory_order_acquire);
    const std::size_t tail = tail_.load(std::memory_order_acquire);
    return head - tail;
  }

  static constexpr std::size_t capacity() noexcept { return Capacity; }

  std::uint64_t rejectedWrites() const noexcept {
    return rejectedWrites_.load(std::memory_order_relaxed);
  }

 private:
  std::array<T, Capacity> storage_{};
  alignas(64) std::atomic<std::size_t> head_{0};
  alignas(64) std::atomic<std::size_t> tail_{0};
  std::atomic<std::uint64_t> rejectedWrites_{0};
};

}  // namespace lmm
