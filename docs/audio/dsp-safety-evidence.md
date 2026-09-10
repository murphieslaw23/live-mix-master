# Issue #3 native DSP and callback safety evidence

Status: deterministic source/build evidence. This document **does not satisfy** the physical input or BlackHole device E2E gate.

## Real-time callback boundary

The macOS Core Audio callback chain is:

`captureIoProc` → bounded PCM decode/stereo conversion → `lmm_process_bound_capture_stereo` → channel sum/fader/mute/solo → sample limiter → two bounded SPSC queue writes.

The callback contract is explicit:

- **no heap allocation**: the Core Audio scratch vector is sized before `AudioDeviceStart`; callback-local storage is fixed-size `std::array`/stack data and the PCM queues use compile-time storage.
- **no mutex** or blocking lock: callback state and counters use atomics; producer fan-out uses non-blocking SPSC `tryPush`.
- **no disk I/O**: WAV/file work is downstream of the bounded recorder handoff.
- **no network I/O** or HTTP: metadata/provider work is outside the callback.
- **no logging**: callback code does not print or write diagnostics; telemetry uses bounded atomic counters.
- **no Dart** or isolate communication: Dart polls compact status/meter snapshots from the host side.

Control-plane operations such as device enumeration, Core Foundation string conversion, listener installation, scratch allocation, start/stop, and UI/service work may allocate or block because they execute outside the running IOProc.

## Lock-free atomic proof for the initial target

`native/tests/realtime_atomic_contract_tests.cpp` is built and executed only on Apple in CTest. Its C++17 `std::atomic<T>::is_always_lock_free` static assertions fail compilation if the callback-relevant bool, float, double, uint32, uint64, or size_t atomic representation is not always lock-free on the selected macOS toolchain/architecture.

This is stronger than assuming that `std::atomic` is lock-free because of its name. Windows and Linux are still unverified targets and receive no equivalent platform claim from this test.

## Bounded PCM handoff

The mixer processes at most 16 channels and splits capture into chunks of at most `LMM_PCM_BLOCK_FRAMES` (256 frames). Recorder and fingerprint fan-out uses fixed-capacity SPSC queues. Saturation never blocks the audio callback; rejected writes increment observable recorder/fingerprint rejected-block counters.

Queue overflow is therefore a measurable degradation state, not an unbounded allocation path. The real-device acceptance record requires the rejected-block counters to remain zero for a clean run.

## Metering and limiter evidence

Deterministic CTest coverage exercises silence, sine/impulse/multi-channel summing, mute/solo/fader behavior, RMS/peak telemetry, queue behavior, and the limiter ceiling. The current limiter clamps each output sample to `0.98` linear amplitude and reports whether limiting occurred.

The ABI fields named `true_peak_left/right` currently hold the maximum **post-limiter sample value** observed in a processed block. There is no oversampling/inter-sample reconstruction in the current engine, so this implementation is not a standards-based True Peak/dBTP meter and no LUFS claim follows from it. The safe statement is only that the deterministic sample limiter does not emit samples above its configured ceiling.

## Evidence separation

Passing CTest, compiling the lock-free atomic contract, running the hosted Core Audio catalog probe, and launching the Flutter app in CI are necessary engineering gates. They **do not satisfy** the required physical/BlackHole 10-second route, recording, telemetry, removal, and reconnect acceptance. That result belongs only in `docs/audio/issue3-device-acceptance-record.md` after a real host run.
