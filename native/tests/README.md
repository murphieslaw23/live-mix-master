# Native deterministic test gates

These tests are intentionally split from the device E2E acceptance gate.

- `engine_signal_tests.cpp` dynamically loads the built native library and verifies the public C ABI plus deterministic DSP behavior. Dynamic lookup lets the RED phase fail as a test assertion when an expected symbol is absent instead of failing at link time.
- `spsc_ring_buffer_tests.cpp` fails explicitly while the fixed-capacity handoff header is absent, then exercises FIFO, exact-capacity rejection, wraparound, and overflow accounting once implemented.

Passing these tests proves deterministic native contracts only. It does not prove Core Audio device capture or BlackHole/physical-device E2E.
