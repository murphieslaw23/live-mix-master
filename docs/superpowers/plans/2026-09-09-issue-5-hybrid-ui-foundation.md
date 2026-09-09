# LiveMixMaster Issue #5 Hybrid UI Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the merged Issue #1 repository-first design contract into an executable Flutter design system with deterministic token mapping, accessible shared controls, an operator state machine, refactored existing views, and Flutter-rendered golden coverage.

**Architecture:** Keep semantic truth in `design/*.json` and map it into a small `lib/design/` layer. Production widgets consume only `LiveMixTokens`/`LiveMixTheme` and shared `Lmm*` controls; operator recovery behavior is represented by a deterministic state machine independent from UI rendering. Existing mixer, patchbay, and compact monitor views are refactored incrementally rather than replaced wholesale.

**Tech Stack:** Flutter/Dart, `flutter_test`, Material 3, GitHub Actions on `macos-latest`.

**Spec:** `docs/design/hybrid-source-of-truth.md`, `design/tokens.json`, `design/component-states.json`, `design/operator-journey.json`, GitHub Issue #5.

## Global Constraints

- Repository token values are authoritative over artwork.
- Minimum interactive target: 44 px.
- Critical operational state must use icon + text + shape + color; color alone is insufficient.
- Focus indicator: 2 px; copper may be used on base/rack, while strip surfaces require the documented primary-text fallback/outer edge.
- Meter scale: `0, -6, -12, -18, -24, -36, -60` dBFS.
- Desktop master module remains visible while channel strips scroll.
- Generated secondary boards are composition references only, never semantic/copy truth.
- No production code is added before a failing test demonstrates the missing behavior.

---

### Task 1: Token Contract and Theme

**Files:**
- Create: `test/design_contract_test.dart`
- Create: `lib/design/live_mix_tokens.dart`
- Modify: `lib/main.dart`

**Interfaces:**
- Produces: `LiveMixTokens`, `LiveMixTextStyles`, `LiveMixTheme.dark()`.
- Consumes: exact values in `design/tokens.json`.

- [ ] **Step 1: Write the failing contract test**

Test reads `design/tokens.json`, asserts exact ARGB values and key metrics, then expects `LiveMixTokens`/`LiveMixTheme` symbols that do not yet exist.

- [ ] **Step 2: Run CI and verify RED**

Open a draft PR with only the test/plan change. Expected: Flutter Analyze and/or the new design test fails because `lib/design/live_mix_tokens.dart` is missing.

- [ ] **Step 3: Add the minimal token/theme implementation**

Create constants for every canonical color, spacing/radius arrays, meter scale, minimum target and focus width. Define deterministic text-style roles using the approved family names and expose `ThemeData dark()`.

- [ ] **Step 4: Refactor `main.dart` to consume `LiveMixTheme.dark()`**

No feature-local color changes yet.

- [ ] **Step 5: Run the design contract test and full CI; require GREEN**

### Task 2: Operator Journey State Machine

**Files:**
- Create: `test/operator_journey_test.dart`
- Create: `lib/design/operator_journey.dart`

**Interfaces:**
- Produces: `OperatorStage`, `RecoveryEvent`, `OperatorJourneyController`, `transitionTo(...)`, `recover(...)`.
- Consumes: transition/recovery semantics from `design/operator-journey.json`.

- [ ] **Step 1: Write failing transition/recovery tests**

Cover success path, cancel/back from route/correct/export/finalize, device-loss/no-signal/clipping recovery, recording write failures, invalid credentials, reconnecting/failed broadcast, and no-match/offline lookup invariants.

- [ ] **Step 2: Verify RED in CI**

Expected failure: missing operator-journey implementation.

- [ ] **Step 3: Implement minimal deterministic controller**

No I/O; state transitions only. Broadcast failure must not imply recording failure. Fingerprint no-match/offline remains retryable.

- [ ] **Step 4: Verify GREEN and run full CI**

### Task 3: Accessible Shared Component/State Catalog

**Files:**
- Create: `test/design_system_semantics_test.dart`
- Create: `lib/design/widgets/lmm_controls.dart`

**Interfaces:**
- Produces: `LmmStatusTone`, `LmmStatusBadge`, `LmmToggleControl`, `LmmStereoMeter`, `LmmFader`, `LmmTrimKnob`, `LmmFingerprintHud`, `LmmSessionRow`, `LmmDeviceStatus`, `LmmPreflightCheck`.
- Consumes: `LiveMixTokens` and contract state names.

- [ ] **Step 1: Write failing widget/semantics tests**

Assert minimum 44 px target sizing, semantic labels/values, disabled semantics, keyboard activation for toggle controls, focus visibility, explicit ON/OFF text, device/preflight status text, and meter labels/value semantics.

- [ ] **Step 2: Verify RED**

Expected failure: shared widgets are missing.

- [ ] **Step 3: Implement the minimal accessible components**

Every status component includes icon + text + shaped boundary + semantic color. Controls use `Semantics`, `FocusableActionDetector` or Material controls as appropriate. Do not introduce custom paint unless required.

- [ ] **Step 4: Verify widget/semantics tests GREEN**

### Task 4: Refactor Existing Views onto the Shared Contract

**Files:**
- Modify: `lib/features/mixer/mixer_desk_view.dart`
- Modify: `lib/features/monitor/compact_monitor_view.dart`
- Modify: `lib/features/patchbay/patchbay_routing_modal.dart`
- Modify: `test/mixer_user_flow_test.dart`

**Interfaces:**
- Consumes: `LiveMixTokens`, `LiveMixTheme`, shared `Lmm*` controls.
- Preserves: existing recording/fingerprint/patchbay service integration.

- [ ] **Step 1: Extend `mixer_user_flow_test.dart` with failing design-contract assertions**

Assert explicit `MUTE OFF`/`SOLO OFF` semantics, 44 px action targets, separate recording/broadcast semantics, master module persistence at desktop width, and patchbay actions styled through the shared token layer.

- [ ] **Step 2: Verify RED**

Expected failures must correspond to missing semantics/shared controls, not unrelated service behavior.

- [ ] **Step 3: Refactor MixerDeskView**

Remove feature-local canonical color constants. Use shared toggles/statuses/meters while preserving horizontal channel scrolling and fixed master module.

- [ ] **Step 4: Refactor CompactMonitorView**

Use shared tokens/statuses/meters, text/primary for healthy copy, and explicit recording/broadcast semantics.

- [ ] **Step 5: Refactor PatchbayRoutingModal**

Use shared theme/tokens for primary action, surfaces, focus and labels while preserving current routing behavior.

- [ ] **Step 6: Verify user-flow + semantics tests GREEN and run full CI**

### Task 5: Deterministic Flutter Goldens and CI Gate

**Files:**
- Create: `test/design_goldens_test.dart`
- Create after generation: `test/goldens/mixer_desktop.png`
- Create after generation: `test/goldens/mixer_tablet.png`
- Create after generation: `test/goldens/monitor_phone.png`
- Create after generation: `test/goldens/monitor_compact.png`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Produces deterministic pixel evidence for the approved desktop/mobile baselines and responsive tablet/compact behavior.

- [ ] **Step 1: Add golden tests without baselines and verify RED**

Render `MixerDeskView` at 1440x1000 and 1024x768, and `CompactMonitorView` at 390x844 and 700x600 using deterministic fixture values.

- [ ] **Step 2: Add a temporary PR-only generation job**

Run `flutter test --update-goldens test/design_goldens_test.dart` on `macos-latest` and upload `test/goldens/*.png` as an artifact. Keep the normal golden-test job failing until baselines are committed.

- [ ] **Step 3: Download and visually inspect generated artifacts**

Reject any overflow, clipped status copy, missing master module, or contradictory state presentation.

- [ ] **Step 4: Commit inspected PNG baselines**

Use repository binary blobs/tree commit; do not hand-author image bytes.

- [ ] **Step 5: Remove the temporary generator and enable the permanent design-system CI job**

Permanent command: `flutter test test/design_contract_test.dart test/operator_journey_test.dart test/design_system_semantics_test.dart test/design_goldens_test.dart`.

- [ ] **Step 6: Verify full CI GREEN**

### Task 6: Evidence and Handoff

**Files:**
- Update GitHub Issue #5
- Update Notion implementation tracker
- No Vercel deployment unless a Vercel project becomes linked to this Flutter repository.

- [ ] **Step 1: Record exact completed scope and known gaps**

Do not close Issue #5 unless all required secondary workflow/recovery screens have deterministic executable fixtures; otherwise keep it open and identify the remaining tranche.

- [ ] **Step 2: Verify Vercel linkage status**

If `murphieslaw23/live-mix-master` remains unlinked, record that no deployment gate applies to this desktop Flutter tranche.

- [ ] **Step 3: Update Notion with branch/PR/CI/golden evidence**

- [ ] **Step 4: Finish branch only after fresh verification**
