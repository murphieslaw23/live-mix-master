# Tested-artifact Vercel promotion

This is the W5 deployment path for Flutter Web. It deliberately deploys the already-tested
`live-mix-master-web` artifact rather than causing Vercel to run a second Flutter build.

## Preconditions

1. The source commit has a successful **Web Release Compile Contract** workflow and already
   contains this promotion workflow, `vercel.json`, and the required `api/` sources.
2. Record the workflow run ID, commit SHA, artifact ID, and the artifact digest reported by
   GitHub Actions. The promotion checks that all four values describe the same unexpired
   `live-mix-master-web` artifact.
3. Configure the repository environment secret `VERCEL_TOKEN` in both
   `vercel-preview` and `vercel-production`. It must be an access token scoped only to
   the SYCO23 Vercel team.
4. Add only server-side values in the Vercel project:
   - `ACOUSTID_API_KEY` if fingerprint lookup is being enabled;
   - `LMM_BROADCAST_DESTINATIONS_JSON` only for approved public HTTPS destinations.
   Local and LAN destinations must remain absent and return the documented local-bridge
   state.

No browser credential, provider key, destination URL, or authorization material is accepted by
this promotion workflow.

## Promotion

Run **Promote tested Web artifact** manually and provide:

- `artifact_id`
- `artifact_digest` in `sha256:<hex>` form
- `commit_sha`
- `target`: first `preview`, then `production` after the W5 browser, PWA, and
  accessibility gates are signed off.

The workflow:

1. checks out the exact commit and confirms it contains the versioned Vercel configuration;
2. fetches the artifact metadata and rejects a name, SHA, digest, or expiration mismatch;
3. downloads the immutable artifact and verifies its archive SHA-256 digest;
4. reconstitutes `build/web` without invoking Flutter;
5. adds only the versioned Vercel API route sources from that same commit;
6. deploys to the existing `live-mix-master` Vercel project and resolves the resulting hostname
   to its immutable Vercel deployment ID;
7. verifies the protected release shell and sends side-effect-free authenticated `POST {}` probes
   to `/api/fingerprint-lookup` and `/api/broadcast-metadata`; each probe must reach the route and
   return the expected `invalidRequest` or `invalidConfiguration` JSON state, so no external
   provider or broadcast destination is contacted;
8. records only non-secret target, commit, artifact, deployment-ID, and URL evidence in the
   GitHub job summary.

A preview deployment is not a release candidate. Production promotion remains blocked until
the browser E2E matrix, PWA/offline checks, and accessibility checks are fresh and linked to
the same tested artifact.

## Current production evidence

The W5 production promotion completed on 2026-09-11 with:

- tested release commit: `4f97a354dac54cf7c103f477d65002e7dff87213`
- source CI run: `34617452995`
- artifact ID: `10270868244`
- artifact digest: `sha256:eb919bafdc9519e56f09d0d5acaaac28ec568391b55f04ed6b398a799ec7a77a`
- production promotion run: `34622067734`
- Vercel deployment ID: `dpl_BV4vsKBS6Bnzu2Uk5J75nhpHfv9L`
- production alias: <https://live-mix-master.vercel.app>

Later documentation or promotion-tooling commits on `main` do not change this release identity.
A new application release requires a new tested artifact and a new explicit promotion.
