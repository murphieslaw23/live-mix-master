# Broadcast diagnostic safety — Batch 1

Date: 2026-10-07
Scope: A1 credential redaction and A2 public destination identities.

## Public diagnostic boundary
Broadcast failure messages are allowlisted by ServiceFailureCode. Raw exception strings, request/response bodies, authorization values, URLs, mount strings and filesystem paths must not populate public ServiceStatus messages or BroadcastAdapterResult diagnostics. Results expose diagnosticCode as broadcast.<failureCode> for safe classification.

## Destination identities
Each adapter receives a process-local monotonic identifier independent of all destination input. Public identities are <protocol>:destination-<number>. They remain stable for that adapter and are not durable cross-restart IDs, URL hashes, user labels, or routing inputs. No hostname is included. Persisted destination IDs can be integrated later under a separate validation contract.

## Legacy text sanitization
redactBroadcastDiagnostic delegates to redactDiagnostic. The shared helper removes full scheme URLs, complete Authorization/Proxy-Authorization values before generic assignments, standalone Basic/Bearer credentials and recognized password/token assignments. Oversized input (>2048 UTF-16 code units) is replaced entirely. Remaining control characters are normalized. This is defense in depth, not a claim that arbitrary unlabeled secrets can be detected.

## Compatibility
HTTP methods, endpoint schemes, paths, authentication placement, mount normalization, webhook JSON fields, timeout/retry defaults and local overlay output remain unchanged. Former public endpoint strings intentionally change to opaque IDs. Cancellation, concurrent update ordering, synchronous status delivery and configuration validation are not remediated by Batch 1.

## Tests and evidence
Existing provider payload, auth, retry, overlay and redaction coverage remains in test/broadcast_metadata_adapter_test.dart with opaque-identity expectations. Added regressions cover complete authorization headers, quoted credentials, URLs, controls, size limits, idempotence, per-provider identities, client-exception retries/status/results, response-body exclusion and overlay path exclusion. Tests are staged, not yet executed on the new commit; exact-head CI evidence is required before closing A1/A2. Prior persistence CI does not validate these changes. No production deployment or Notion completion update is part of this commit.
