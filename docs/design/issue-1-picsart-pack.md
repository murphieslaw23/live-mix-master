# Issue #1 — Picsart design pack and Canva replacement evaluation

Status: **full static view coverage exists; exact-token desktop/mobile baselines are approved for Phase 1 review; secondary generative boards are layout references only**.

This document inventories the Picsart visual work for GitHub Issue #1. Semantic tokens, reusable state vocabulary and interaction behavior are now repository-owned; see `docs/design/hybrid-source-of-truth.md` and `design/*.json`.

## Design direction

Dark industrial rack surfaces, mechanical/totemic cues, thin cold-gray separators, restrained worn-metal texture, explicit state labels, and no terminal chrome, glossy startup-card styling, neon/cyberpunk gradients, or vinyl metaphors.

Canonical token values live in `design/tokens.json` rather than in generated image pixels.

## Picsart Drive

Folder: **LiveMixMaster — Issue #1 Design Pack** (`dde8670a-9ba1-484b-a607-250ddbe4f525`).

## Preferred visual baselines

These are the current deterministic pixel references. They were normalized to the repository action/warning tokens and uploaded back to the Picsart design folder.

- Desktop mixer: https://gcdn.picsart.com/editing-temp/2714c23d-9be0-4a2d-a670-ec25215a872c.png
- Mobile/read-only field monitor: https://gcdn.picsart.com/editing-temp/39afcc9a-10ea-4f2d-9b84-6d7473c6357e.png

Earlier corrected scene renders remain useful provenance:

- Desktop corrected scene render: https://gcdn.picsart.com/media-engine/6ec45119-7706-4b87-bedc-983cea7d30ca.png
- Phone corrected scene render: https://gcdn.picsart.com/media-engine/f51e2b8c-e83a-42a5-901e-c358d18953e3.png

## Brand assets

- Clean primary totem PNG: https://gcdn.picsart.com/cloud-storage/d0965d0f-22e2-459c-a62f-c049d4e050fb.png
- Primary totem SVG: https://gcdn.picsart.com/editing-temp/2a6e52db-d83e-47b4-b520-07cf2b6a4ea8.svg
- Inverse totem PNG: https://gcdn.picsart.com/pipeline-output/2ac406f6-aaba-4ff9-a205-e0b2c051037f.png
- Inverse totem SVG: https://gcdn.picsart.com/editing-temp/5f7e6fbf-6690-42ff-ae39-31a37a1a175a.svg
- Compact icon PNG: https://gcdn.picsart.com/pipeline-output/e677a72f-ff22-4ea1-b1d4-a86a44f5b97f.png
- Compact icon SVG: https://gcdn.picsart.com/editing-temp/dfb8d32a-23fc-48d0-9933-ecc683ccdf1f.svg

## Secondary layout/art-direction references

These cover every required workflow/view family, but strict visual QA found generated text and combined-state contradictions. Therefore they guide **composition, density, hierarchy and art direction only**. Copy/state truth comes from `design/component-states.json` and `design/operator-journey.json`.

- Design-system board / Frames 01–07: https://gcdn.picsart.com/pipeline-output/9e2a0f3d-3fac-4cf4-a0ad-d5affab5d19e.png
- Launch / session start: https://gcdn.picsart.com/pipeline-output/aec8e4cd-3dfe-47bb-99af-22837decdb7f.png
- Patchbay: https://gcdn.picsart.com/pipeline-output/f42e8f67-83cd-459e-be20-f720f6ef151d.png
- Session + fingerprint + correction + export + finalize: https://gcdn.picsart.com/pipeline-output/c5327e8b-8df4-42c4-9b37-4089f0a5fc93.png
- Settings + output preflight: https://gcdn.picsart.com/pipeline-output/96cc04bd-768f-4a74-9c78-8937e8557e7d.png
- Recovery-state matrix: https://gcdn.picsart.com/pipeline-output/1bee7466-8b57-443a-bd19-c43077605318.png
- Tablet field monitor: https://gcdn.picsart.com/pipeline-output/2173d533-9e40-4a49-9f60-30750bb2f7ee.png
- Compact/narrow-window desktop monitor: https://gcdn.picsart.com/pipeline-output/8f11e05f-0cbb-4eb1-a286-bbf394e238ea.png
- Operator journey / interaction map: https://gcdn.picsart.com/pipeline-output/006fed27-db71-48cc-80d1-bfbe5f259a51.png

Detailed reject reasons and contrast checks are recorded in `docs/design/visual-qa-2026-09-09.md`.

## Scope coverage

The visual pack covers launch/new/open session; source/device patching; desktop mixing and metering; recording/broadcast preflight and status; session/fingerprint review; manual correction; export; recording finalization; settings; all required recovery families; phone/tablet/compact monitoring; and the complete success/cancel/back/recovery operator journey.

Coverage is not the same as pixel approval. Desktop and mobile baselines are the preferred approved visual fixtures; deterministic Flutter golden fixtures for the secondary screens are an Issue #5 deliverable.

## Canva vs Figma decision

The original issue coupled semantic variables, reusable components, interaction prototype and visual review to Figma. That coupling has now been removed.

### Hybrid source of truth

1. Picsart/Canva — visual composition and collaborative review.
2. `design/tokens.json` — exact semantic token/typography/contrast contract.
3. `design/component-states.json` — reusable UI component/state vocabulary.
4. `design/operator-journey.json` — canonical success/cancel/error/recovery graph.
5. Flutter widget, semantics, interaction and golden tests in Issue #5 — executable implementation evidence.

Figma is optional. If used, node/component IDs are supplemental references rather than completion requirements.

The Canva `image-to-design` pilot could not complete because the connection required authorization/login in this session, so no import-fidelity claim is made. Canva import remains optional and is not a semantic gate.

## Current Phase 1 gate

The repository contracts and exact-token desktop/mobile baselines are present. Strict QA has also identified and documented the limitations of every generative secondary board. The remaining decision is human approval of this hybrid contract and the explicit delegation of deterministic secondary view fixtures to Issue #5.
