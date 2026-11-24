# Broadcast configuration validation — A5

Date: 2026-10-07. Status: implementation candidate; exact-head CI required.

Runtime validation happens before running/retrying status, HTTP calls or overlay writes. Invalid config emits one failed status and result with invalidConfiguration, zero attempts and allowlisted diagnostics. validationIssue identifies the rejected field without including its value; validationFailure remains compatible.

Limits: timeout >0 and <=60 seconds; maxRetries 0..5 (one initial attempt plus retries); initialBackoff >=0 and <=maxBackoff; maxBackoff >0 and <=30 seconds. Default values remain 4 seconds, 2 retries, 100 milliseconds initial delay and 30-second cap. retryDelay validates attempt bounds and caps exponential growth.

Icecast/SHOUTcast: host must be ASCII hostname, strict IPv4 or IPv6 (bracketed IPv6 accepted); reject URLs, userinfo, whitespace, zone identifiers and path/query/fragment components. Ports are 1..65535. Icecast mount is nonempty, <=1024 characters, contains no whitespace, controls, backslash, question mark or fragment delimiter, and is not a URL or authority. Leading slash normalization and query encoding remain. Existing HTTP transport and credential placement are unchanged.

Webhooks: HTTPS by default. Existing HTTP configurations must deliberately set allowHttpWebhook=true for trusted local/development use; this is not a cloud SSRF exemption. Userinfo and fragments are rejected. Valid path/query values remain routing inputs and never public identities. Host syntax and port are checked. No automatic HTTPS upgrade or credential stripping occurs.

Overlay: null selects live_current_track.txt. Explicit empty/whitespace-only or NUL-containing paths are rejected. Validation performs no I/O; missing parents, permissions and storage failures remain runtime write failures. Optional overlayWriter injection proves zero writes for invalid inputs without changing default UTF-8 output.

Config and BroadcastProtocol move into broadcast_server_config.dart, which imports no dart:io/ffi. The adapter re-exports the module to preserve existing imports. Existing broadcast/security tests and persistence fixes remain. A5 cases are registered by the existing CI-selected broadcast_pipeline_test.dart; no new CI workflow or deployment is introduced.

This does not implement A3 cancellation, A4 ordering, DNS pinning, server-side SSRF prevention, authentication/authorization or release acceptance. Notion completion and Vercel promotion require separate evidence and approval.
