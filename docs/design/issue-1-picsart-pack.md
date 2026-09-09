# Issue #1 — Picsart design pack and Canva replacement evaluation

Status: **visual coverage complete as static design exploration; Phase 1 acceptance remains open**.

This document records the Picsart work produced for GitHub Issue #1 on 2026-09-09. It is evidence for review, not a claim that the Figma acceptance criteria or Flutter visual parity are complete.

## Design direction

The pack follows the existing LiveMixMaster handoff direction: dark industrial rack surfaces, mechanical/totemic cues, thin cold-gray separators, restrained worn-metal texture, explicit state labels, and no terminal chrome, glossy startup-card styling, neon/cyberpunk gradients, or vinyl metaphors.

Required semantic colors retained in the briefs:

- `surface/base` — `#111315`
- `surface/rack` — `#1C1F23`
- `surface/strip` — `#24292F`
- `accent/ochre` — `#D96528`
- `accent/copper` — `#2A7A6D`
- `status/warn` — `#D48822`
- `meter/nominal` — `#22C55E`
- `meter/headroom` — `#EAB308`
- `meter/clip` — `#EF4444`
- `meter/inactive` — `#1A1D20`
- `text/primary` — `#E6EDF3`
- `text/secondary` — `#8B949E`

## Picsart asset inventory

Picsart Drive folder: **LiveMixMaster — Issue #1 Design Pack** (`dde8670a-9ba1-484b-a607-250ddbe4f525`).

### Brand and component foundations

- Design-system board / Frames 01–07: https://gcdn.picsart.com/pipeline-output/9e2a0f3d-3fac-4cf4-a0ad-d5affab5d19e.png
- Clean primary totem PNG: https://gcdn.picsart.com/cloud-storage/d0965d0f-22e2-459c-a62f-c049d4e050fb.png
- Primary totem SVG: https://gcdn.picsart.com/editing-temp/2a6e52db-d83e-47b4-b520-07cf2b6a4ea8.svg
- Inverse totem PNG: https://gcdn.picsart.com/pipeline-output/2ac406f6-aaba-4ff9-a205-e0b2c051037f.png
- Inverse totem SVG: https://gcdn.picsart.com/editing-temp/5f7e6fbf-6690-42ff-ae39-31a37a1a175a.svg
- Compact icon PNG: https://gcdn.picsart.com/pipeline-output/e677a72f-ff22-4ea1-b1d4-a86a44f5b97f.png
- Compact icon SVG: https://gcdn.picsart.com/editing-temp/dfb8d32a-23fc-48d0-9933-ecc683ccdf1f.svg

### Operator views

- Launch / session start: https://gcdn.picsart.com/pipeline-output/aec8e4cd-3dfe-47bb-99af-22837decdb7f.png
- Patchbay / Frame 08: https://gcdn.picsart.com/pipeline-output/f42e8f67-83cd-459e-be20-f720f6ef151d.png
- Corrected desktop mixer / Frame 09: https://gcdn.picsart.com/media-engine/6ec45119-7706-4b87-bedc-983cea7d30ca.png
- Session + fingerprint + correction + export + finalize board / Frame 10: https://gcdn.picsart.com/pipeline-output/c5327e8b-8df4-42c4-9b37-4089f0a5fc93.png
- Settings + output preflight: https://gcdn.picsart.com/pipeline-output/96cc04bd-768f-4a74-9c78-8937e8557e7d.png
- Recovery-state matrix: https://gcdn.picsart.com/pipeline-output/1bee7466-8b57-443a-bd19-c43077605318.png
- Corrected phone field monitor / Frame 11: https://gcdn.picsart.com/media-engine/f51e2b8c-e83a-42a5-901e-c358d18953e3.png
- Tablet field monitor: https://gcdn.picsart.com/pipeline-output/2173d533-9e40-4a49-9f60-30750bb2f7ee.png
- Compact/narrow-window desktop monitor: https://gcdn.picsart.com/pipeline-output/8f11e05f-0cbb-4eb1-a286-bbf394e238ea.png
- Operator journey / interaction map: https://gcdn.picsart.com/pipeline-output/006fed27-db71-48cc-80d1-bfbe5f259a51.png

## Scope coverage

The static design pack now has visual coverage for:

- launch/new/open session;
- source/device patching and device-loss recovery;
- full desktop mixer and master metering;
- recording and broadcast preflight/status;
- session/fingerprint timeline and low/no-match states;
- manual correction;
- export;
- recording finalization;
- settings;
- all required recovery families: no device, permission denied, device lost, no signal, clipping, disk full, write failure, offline/no-match lookup, invalid credentials, reconnecting/failed stream;
- phone, tablet and compact narrow-window monitoring;
- success, cancel/back and recovery branches in the operator journey.

The corrected desktop and phone fixtures are stronger evidence than the purely generative boards because their meter/button/status overlays were authored deterministically and previously validated as Picsart media scenes. The newly generated boards are **design references** and still require exact text/token/contrast inspection before approval.

## Canva vs Figma

### What Canva can cover

The connected Canva capability can support visual review and presentation work: editable fixed-page designs, text/media editing, element position/size changes, comments, Brand Kit workflows, resizing, and image-to-editable-design conversion for flat artwork.

### What is not equivalent to Issue #1's Figma requirement

The current Issue #1 definition of done requires a semantic UI source of truth with reusable components/variants, clickable interaction states, and final Figma component/node IDs for developer handoff. The exposed Canva editing surface is not equivalent to that contract. In particular, the available editing operations do not provide a Figma-like semantic variable system, reusable UI component/variant graph, developer node/component IDs, or a complete application-prototype state model. The plugin editing surface also does not expose some structural operations expected from a UI-system tool, such as font-family changes, adding arbitrary new text elements, changing backgrounds/gradients, page reordering, animation/transition editing, grouping, or arbitrary shape restyling.

A pilot `image-to-design` conversion of the Picsart design-system board was attempted, but the Canva connection required user authorization/login and the conversion could not be completed in this session. Therefore no claim is made about conversion fidelity.

### Decision

**Canva should not be treated as a drop-in replacement for Figma under the current Issue #1 acceptance criteria.** It can replace Figma only if the definition of done is changed to a hybrid handoff, for example:

1. Picsart/Canva for visual compositions and review;
2. repository-owned semantic token manifest and component/state specification;
3. repository-owned operator journey/state map;
4. Flutter widget catalog + golden tests as the executable component source of truth;
5. Canva design/page IDs instead of Figma node IDs where useful.

Until such a change is explicitly accepted, Issue #1 remains open and Issue #5 should remain blocked from claiming Figma-approved parity.

## Review gates still open

- Verify exact colors, typography and contrast on all newly generated boards.
- Validate compact/inverse logo readability at the required minimum size rather than relying on the generation brief.
- Convert static component examples into a genuinely reusable semantic component system, or formally amend the acceptance criteria to the hybrid repository-first handoff above.
- Produce an actually clickable prototype if Figma remains the source of truth.
- Record approval evidence before starting visual-parity claims in Flutter.
