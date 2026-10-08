# Server outbound SSRF audit — RED contract stage

Date: 2026-10-07. Baseline: e52a98f1f8aa1bb50ca154bf73c6329e9ac539ce.

The prior adapter/service/browser CI batch passed its reported executed checks, but did not remediate server-side SSRF. This commit adds regression contracts only. Failures are expected against the existing APIs; RED is not observed until tests execute. Keep the PR draft and do not deploy this intermediate stage.

Existing six broadcast API contracts and corrected bodyless 204 fixtures remain unchanged except importing the security regression module. Added ten cases cover unspecified/mapped IPv6, ordinary fc/fd hostnames, URL userinfo, private DNS, mixed DNS, retry revalidation and explicit redirect rejection in both APIs. All transport/resolution fixtures are mocked. The public-address fixture is never contacted. No internal service, cloud metadata endpoint or real DNS-rebinding probe is exercised.

The proposed resolveImpl seam returns Node-style address/family records and must be invoked before each broadcast attempt. Prohibited local DNS/literal results retain the safe localBridgeRequired response with no outbound request. Invalid URL userinfo is an invalidConfiguration result. Allowed requests pass redirect:error to the transport. Production must not substitute an ordinary second-resolving fetch after validation.

Next implementation: parsed IPv4/IPv6 public-address policy; bounded cancellable resolution; exact-destination validation; connection-bound approved DNS lookup; redirects disabled; response limits; safe errors. Existing test-only fetch injection must be kept separate from production guarded transport. Connection-level tests must prove the actual socket lookup uses validated results, preserves TLS hostname verification and does not re-resolve. These ten API-level tests alone do not prove DNS pinning or deployment egress safety.

Remaining review: runtime/egress evidence, authentication/authorization, rate and body limits, full address-range policy and connection-time DNS/redirect tests. No SSRF finding is closed by this test-only commit.
