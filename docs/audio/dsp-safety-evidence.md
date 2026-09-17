# Issue #3 native DSP and callback safety evidence

Status: deterministic source/build evidence. This document **does not satisfy** the physical input or BlackHole device E2E gate.

## Real-time callback boundary

The macOS callback path is:

`Core Audio IOProc` → bounded PCM decode/pair selection → `lmm_process_bound_capture_stereo` → shared `dsp_kernel.hpp` mix/fader/trim/mute/solo/master processing → deterministic sample limiter → bounded recorder/fingerprint SPSC handoff.

The callback contract is explicit:

- **no heap allocation**: Core Audio scratch storage is prepared before `AudioDeviceStart`; callback-local staging uses fixed-size stack/array storage and bounded native queues.
- **no mutex** or blocking lock: callback-visible control/meter state uses atomics and producer fan-out uses non-blocking SPSC writes.
- **no disk I/O**: WAV work occurs after the bounded recorder handoff on the Dart host side.
- **no network I/O**: fingerprint/provider work is outside the callback.
- **no logging**: callback code does not print or serialize diagnostics; timing/queue state is published through bounded counters/snapshots.
- **no Dart**: Dart performs control calls and status polling only from the non-real-time host side.

Control-plane operations such as device enumeration, Core Foundation string work, permission handling, listener installation, allocation during start/stop, process launching for System Settings, and Flutter/service work execute outside the running IOProc.

## Lock-free atomic proof for the initial target

`native/tests/realtime_atomic_contract_tests.cpp` contains `is_always_lock_free` assertions for the callback-relevant atomic types on Apple builds, including `std::atomic<float>`, `std::atomic<double>`, and `std::atomic<std::uint64_t>`. A toolchain/architecture that cannot satisfy those assertions fails the native test build rather than silently weakening the callback claim.

This is a macOS-targeted claim only; it must not be generalized to unverified Windows/Linux targets.

## Bounded PCM handoff

The native engine supports at most 16 channels internally. The current macOS host deliberately exposes exactly one active Core Audio capture route. Recorder and fingerprint fan-out use fixed-capacity SPSC queues; saturation never blocks the callback and instead increments observable rejected-block counters.

Queue overflow is therefore a measurable degradation state rather than an unbounded allocation path. The real-device acceptance run requires recorder and fingerprint rejected-block counters to remain zero for a clean result.

## Shared DSP and limiter evidence

Native desktop processing uses the canonical `native/dsp_kernel.hpp` kernel also used to produce the Web parity/Wasm contract. Deterministic native tests cover mix control behavior, metering, bounded queue behavior, capture conversion, selected channel-pair conversion, and the limiter/sample-ceiling contract.

The current ABI fields named `true_peak_left/right` contain post-limiter **sample peak** values. There is no oversampled inter-sample reconstruction in this implementation, so this is not standards-based True Peak/dBTP metering and no LUFS claim follows from it.

## Evidence separation

Passing analyzer, Flutter tests, native CTest, lock-free atomic assertions, hosted Core Audio probe work, Web/shared-DSP parity checks, packaging, and hosted launch smoke are necessary engineering gates. They **do not satisfy** the required real physical/BlackHole >=10-second route, recording, same-process telemetry, removal, and reconnect acceptance. That result belongs only in `docs/audio/issue3-device-acceptance-record.md` after a real macOS host run.
