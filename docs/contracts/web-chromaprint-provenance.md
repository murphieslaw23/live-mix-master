# Web Chromaprint provenance

This document records the reproducible inputs for the LiveMixMaster Web fingerprint-preparation artifact. It is engineering provenance, not a legal-compliance determination.

## Upstream source

- Project: Chromaprint / AcoustID
- Version: `v1.6.1`
- Release date: 2026-07-28
- Source archive: `chromaprint-1.6.1.tar.gz`
- Expected SHA-256: `3368805af0ee47b9df74df10b5001a44569e01df2844dab520031720dde9ad23`
- Reference CLI for parity: `chromaprint-fpcalc-1.6.1-linux-x86_64.tar.gz`
- Reference CLI SHA-256: `fc16cd37a70168040bc9ceb45f1d4d1216f5a75bc4c9cf8564bea70ac6a45733`

The build script refuses to compile the source archive unless its digest matches exactly.

## Toolchain

- Emscripten SDK: `6.0.9`
- CMake build type: `Release`
- `BUILD_SHARED_LIBS=OFF`
- `BUILD_TOOLS=OFF`
- `BUILD_TESTS=OFF`
- `USE_INTERNAL_AVRESAMPLE=ON`
- `FFT_LIB=kissfft`
- `KISSFFT_ROOT=<Chromaprint source>/src/3rdparty/kissfft`

The Web artifact does not link FFTW and does not require a browser-side FFmpeg runtime.

## LiveMixMaster wrapper ABI

Source: `web/fingerprint/chromaprint/lmm_chromaprint_wrapper.cpp`

Exported native functions:

- `lmm_chromaprint_version()`
- `lmm_chromaprint_fingerprint(const int16_t*, int, int, int)`
- `lmm_chromaprint_free(void*)`
- Emscripten `_malloc` / `_free`

The wrapper uses the public Chromaprint API with `CHROMAPRINT_ALGORITHM_DEFAULT`. Input is interleaved signed PCM16. The generated encoded fingerprint is passed unchanged to the existing server-side fingerprint lookup contract.

## Generated artifacts

`tool/build_chromaprint_wasm.sh` produces build-only files under `build/chromaprint-wasm/`:

- `livemixmaster-chromaprint-core.mjs`
- `livemixmaster-chromaprint-core.wasm`
- `livemixmaster-chromaprint.mjs`

They are not hand-edited source. W4 parity CI compares their output against official `fpcalc` 1.6.1 for identical deterministic PCM before the artifacts may be packaged into the Web release.

## Runtime boundary

The intended release runtime is a Dedicated Worker. The AudioWorklet does not instantiate Chromaprint, execute fingerprint computation, perform network I/O, or write storage. Provider credentials stay server-side in `/api/fingerprint-lookup`.

## Licensing review gate

Chromaprint's upstream license documentation states that its own source is MIT-licensed but the project includes FFmpeg-derived code under LGPL 2.1 and should as a whole be considered LGPL 2.1; it also instructs distributors to consider the selected FFT library's license. LiveMixMaster therefore treats the generated Wasm artifact as requiring a third-party notice/source-relinkability review before W5 production promotion.

This repository record intentionally does not assert that the final distribution satisfies every applicable license obligation. That determination remains a release gate.