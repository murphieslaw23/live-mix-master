#include <cstdlib>
#include <iostream>

#if __has_include("spsc_ring_buffer.h")
#include "spsc_ring_buffer.h"

namespace {

struct Checks {
  int failures = 0;

  void expect(bool condition, const char* label) {
    if (!condition) {
      ++failures;
      std::cerr << "FAIL: " << label << '\n';
    }
  }
};

}  // namespace

int main() {
  Checks checks;
  lmm::SpscRingBuffer<int, 4> queue;

  int value = -1;
  checks.expect(!queue.tryPop(value), "new queue is empty");
  checks.expect(queue.size() == 0, "new queue size is zero");
  checks.expect(queue.rejectedWrites() == 0, "new queue has no rejected writes");

  checks.expect(queue.tryPush(10), "push first item");
  checks.expect(queue.tryPush(20), "push second item");
  checks.expect(queue.tryPush(30), "push third item");
  checks.expect(queue.tryPush(40), "push fourth item to exact capacity");
  checks.expect(queue.size() == 4, "queue exposes exact compile-time capacity");
  checks.expect(!queue.tryPush(50), "full queue rejects producer instead of blocking");
  checks.expect(queue.rejectedWrites() == 1, "full rejection increments overflow counter");

  checks.expect(queue.tryPop(value) && value == 10, "FIFO pop 10");
  checks.expect(queue.tryPop(value) && value == 20, "FIFO pop 20");
  checks.expect(queue.tryPush(50), "wraparound push 50");
  checks.expect(queue.tryPush(60), "wraparound push 60");
  checks.expect(queue.tryPop(value) && value == 30, "FIFO survives wraparound 30");
  checks.expect(queue.tryPop(value) && value == 40, "FIFO survives wraparound 40");
  checks.expect(queue.tryPop(value) && value == 50, "FIFO survives wraparound 50");
  checks.expect(queue.tryPop(value) && value == 60, "FIFO survives wraparound 60");
  checks.expect(!queue.tryPop(value), "queue returns empty after all pops");
  checks.expect(queue.size() == 0, "queue size returns to zero");
  checks.expect(queue.rejectedWrites() == 1, "successful wraparound does not alter overflow counter");

  if (checks.failures != 0) {
    std::cerr << checks.failures << " SPSC queue checks failed\n";
    return EXIT_FAILURE;
  }
  std::cout << "SPSC ring-buffer contract passed\n";
  return EXIT_SUCCESS;
}

#else

int main() {
  std::cerr << "FAIL: native/include/spsc_ring_buffer.h is missing; fixed-capacity SPSC handoff is not implemented\n";
  return EXIT_FAILURE;
}

#endif
