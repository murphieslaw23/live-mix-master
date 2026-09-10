# Issue #3 RED gate

The first implementation tranche is intentionally test-first.

Expected RED failures before production implementation:

1. `engine_signal_tests` loads `liblive_mixer_engine.dylib` successfully, then fails because the current prototype does not export the required Task 1 processing/control/meter symbols.
2. `spsc_ring_buffer_tests` fails explicitly because `native/include/spsc_ring_buffer.h` does not yet exist.

Neither failure is a device-E2E result. The purpose of this tranche is only to prove that the new tests detect the missing native DSP/queue capabilities before implementation.
