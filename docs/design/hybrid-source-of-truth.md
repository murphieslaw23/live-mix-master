# LiveMixMaster hybrid design source of truth

Status: **adopted for Issue #1 review; final visual approval still pending**.

This document replaces the assumption that a Figma file alone must be the design source of truth. The design contract is split by responsibility so that every important part is versionable, reviewable and testable.

## Authority by layer

1. **Semantic design tokens** — `design/tokens.json`
   - Canonical names and exact values for color, meter scale, spacing, radius, focus, disabled state and minimum interaction target.
   - Generative artwork must never override these values.

2. **Reusable component/state vocabulary** — `design/component-states.json`
   - Canonical component names, required parts and required states.
   - Flutter widgets must implement the same state names and semantics before visual-parity claims.

3. **Interaction and recovery contract** — `design/operator-journey.json`
   - Canonical success, cancel/back, error and recovery transitions.
   - This state graph replaces the clickable-prototype requirement when Figma is not used.

4. **Visual reference layer** — `docs/design/issue-1-picsart-pack.md`
   - Picsart is the current visual-composition source for the Issue #1 screens and state boards.
   - Canva may be used for collaborative fixed-page editing/review after authorization and a successful import check.
   - Visual references are subordinate to semantic token and state contracts when a generated image contains inconsistent copy, color or state behavior.

5. **Executable implementation evidence** — Issue #5
   - Flutter widget catalog, semantics/focus behavior, interaction tests and golden tests are the executable proof that the design contract has been implemented.
   - Golden tests are required before the application may claim visual parity with approved visual references.

## Why this replaces the Figma-only gate

The original Issue #1 definition of done coupled four different concerns to one tool: semantic variables, reusable components, interaction prototype and visual review. The repository-first model separates those concerns while retaining strict evidence:

- JSON contracts replace Figma variables/component-state naming.
- The operator state graph replaces a tool-specific clickable prototype.
- Picsart/Canva provide the visual composition and human review surface.
- Flutter tests provide executable component and interaction proof.

Figma remains optional. If it is used later, Figma node/component IDs are supplemental references rather than completion requirements.

## Required Issue #1 review gates

Issue #1 can be closed only when all of the following are true:

- [x] Semantic token manifest exists in the repository.
- [x] Reusable component/state contract exists in the repository.
- [x] Operator journey and recovery graph exists in the repository.
- [x] Static visual reference coverage exists for launch, patchbay, mixer, session/fingerprint, correction, export, finalization, settings/preflight, recovery states, phone, tablet and compact monitoring.
- [ ] Visual QA confirms exact required token colors in approved reference fixtures.
- [ ] Typography roles and final font-family/metric decisions are recorded without relying on generative text rendering.
- [ ] Accessibility review confirms critical states use icon + text + shape + color, focus indication is visible, and required interaction targets are represented.
- [ ] Logo review confirms primary, inverse and compact variants are legible at minimum size.
- [ ] Human approval outcome is recorded in Issue #1 and Notion.

The Canva import pilot is useful but not a hard gate. A failed or unavailable Canva import does not invalidate this source-of-truth model because the semantic and interaction contracts are repository-owned.

## Issue #5 entry gate

Issue #5 may begin implementation against this hybrid source of truth once Issue #1 records visual approval. Issue #5 must then add:

- token-to-Dart mapping from `design/tokens.json`;
- a widget catalog covering the states in `design/component-states.json`;
- golden fixtures for approved desktop, tablet, phone and compact views;
- interaction tests that exercise transitions in `design/operator-journey.json`;
- keyboard focus order, semantics labels and non-color state reinforcement.

Issue #5 must not silently alter tokens or state vocabulary. Changes require a design-contract update first.
