# Service reliability contract v1

- Status: Proposed implementation contract
- Date: 2026-09-08
- GitHub issue: #4

This document defines behavior before changing the existing recorder, fingerprint, and broadcast service modules. It is not runtime evidence and does not close Issue #4.

## Non-negotiable session rule

A recorder, lookup, metadata-provider, storage, or network failure must never block or stop the mixer/audio callback. Services receive audio and session events through bounded asynchronous handoff. Every rejected item, queue overflow, retry, terminal failure, and recovery must be observable to the session log and UI-facing state layer.

## Common result model

Every external operation must resolve to one of these typed states:

- `idle` — no request or operation is active.
- `running` — accepted for asynchronous work.
- `succeeded` — terminal success, including durable output identifier where applicable.
- `retrying` — retryable failure with attempt count and next retry time.
- `cancelled` — explicitly stopped; not silently converted to success.
- `failed` — terminal failure with a safe user-facing message and a redacted diagnostic code.

Diagnostics must never include credentials, Authorization headers, passwords, bearer tokens, raw provider URLs containing secrets, or unredacted request bodies.

## Recording contract

### Configuration

`RecordingConfig` must validate destination, filename policy, sample rate, channel count, sample format, bit depth, and maximum file/session limits before opening output. Invalid configuration fails before accepting audio.

### Lifecycle

1. `start` creates a pending session record and opens a temporary output.
2. PCM is copied to a bounded writer queue; audio-thread disk writes are prohibited.
3. `stop` drains accepted data, finalizes RIFF/data sizes, atomically promotes the temporary file when possible, and records final duration/bytes.
4. Interruption leaves a recoverable record and never reports a valid completed WAV until header/finalization validation succeeds.

### Required outcomes

- Full disk, missing destination, permission denial, write error, queue pressure, dropped buffers, and finalization failure are distinct observable failures.
- Tests independently parse output WAVs and verify 16-bit PCM, 24-bit PCM, and 32-bit float headers, sizes, byte order, duration, and close behavior.

## Fingerprint and tracklist contract

### Matching

Provider configuration is injected from environment or secure storage. A lookup has an explicit timeout, cancellation token, retry policy, and confidence threshold. Offline, malformed response, rate limit, timeout, and provider failure must produce distinct safe outcomes.

### Tracklist rules

A persisted entry contains: session ID, cue time, source/input identifier, artist, title, provider ID when available, confidence, provenance (`automatic` or `manual`), and timestamps.

- Suppress automatic duplicates within a configured debounce window using normalized artist/title and/or provider ID.
- A manual correction always supersedes automatic matches for its cue. Later automatic responses must not overwrite it.
- Retryable lookup failures preserve the cue and produce a recoverable pending/failed state; they do not erase the session history.

## Broadcast metadata contract

Adapters for Icecast, SHOUTcast, webhook, and OBS/local-overlay output use provider-specific payload builders behind one typed request/result boundary. The boundary validates UTF-8 input, URL/mount-point construction, authorization placement, timeout, cancellation, retry/backoff, and reconnect behavior.

An adapter result records provider kind, attempt count, safe endpoint identity, outcome, and redacted diagnostic. A metadata failure does not alter the audio route or recording lifecycle.

## Export contract

Export operates from persisted session tracklist data, never from only in-memory UI state.

| Format | Required fields | Rules |
|---|---|---|
| CSV | cue time, artist, title, source, confidence, provenance | UTF-8; quote commas, quotes, and line breaks |
| JSON | full persisted tracklist schema plus export metadata | Stable field names; ISO-8601 timestamps |
| M3U | title/cue annotation and playable path/URI only when available | Do not invent media locations |

Rekordbox XML remains deferred until a compatible schema and an import-validation fixture are committed.

## Test matrix

- Unit: PCM conversion, WAV header/finalization, queue-pressure accounting, normalized track de-duplication, manual-correction precedence, payload formatting, and credential redaction.
- Contract: local mock AcoustID-style responses; Icecast, SHOUTcast, webhook, and overlay endpoints; success, timeout, cancellation, rate-limit, malformed, auth, and retry cases.
- Integration: injected master PCM boundary → recorder/fingerprint services → durable tracklist → metadata event, with assertions that the UI/audio producer is not blocked.
- Failure path: storage or network failure preserves mixing, emits observable state, and preserves a recoverable session record.

## Definition of evidence

A contract is fulfilled only when implementation tests pass in CI and their run URL, commit SHA, environment, and known limitations are attached to Issue #4 and the delivery tracker.