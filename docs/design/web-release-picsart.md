# LiveMixMaster Web Release — Picsart References

Date: 2026-09-10
Tracking issue: #16

## Authority boundary

The Web release continues the hybrid repository-first model established by Issue #1.

Authoritative:

- `design/tokens.json`
- `design/component-states.json`
- `design/operator-journey.json`
- deterministic Flutter widget/golden tests

Picsart references are visual/art-direction assets. Generated text, exact token rendering, spacing, and state semantics must be verified in Flutter before release acceptance.

## Web asset folder

Picsart Drive folder: **LiveMixMaster — Web Release**

### Maskable PWA icon

File: `LiveMixMaster-web-maskable-pwa-icon.png`

Source URL:
https://gcdn.picsart.com/pipeline-output/b1b775f3-3cb3-4b11-807c-9407ae970f74.png

Purpose:

- PWA install icon master reference
- browser launcher/home-screen icon
- source for deterministic 192 px and 512 px manifest assets after QA

Required QA before release:

- verify the full totem remains inside the maskable safe area
- inspect at 48 px, 192 px, and 512 px
- verify no accidental text or illegible micro-detail
- verify final exported colors against repository tokens
- create deterministic resized derivatives from one approved master

### Browser states board

File: `LiveMixMaster-web-release-browser-states-board.png`

Source URL:
https://gcdn.picsart.com/pipeline-output/d222d87e-e19a-4448-ac62-54573524d52e.png

Purpose:

Art-direction reference for web-only state families that do not exist in the native desktop flow:

- browser audio permission/capture prompt
- browser capability disclosure
- PWA install prompt
- capture-ended/reconnect state

The board is not a pixel or copy source of truth.

## Web-only deterministic UI states to implement in Flutter

1. Browser audio permission required.
2. Browser audio permission denied.
3. Microphone/USB input available.
4. Tab/window/display audio available.
5. User selected display capture but browser returned no audio track.
6. Browser/OS does not expose system audio.
7. Active `MediaStreamTrack` ended.
8. Reconnect required.
9. PWA install available.
10. PWA installed.
11. PWA install unavailable.
12. Browser storage quota/write failure.
13. Server-side fingerprint/provider unavailable.
14. Server-side broadcast metadata unavailable.

## Design rules

Reuse existing semantic tokens and typography. Do not introduce a separate Web visual language.

- Base: `#111315`
- Rack: `#1C1F23`
- Strip: `#24292F`
- Ochre: `#D96528`
- Copper: `#2A7A6D`
- Warning: `#D48822`
- Signal: `#22C55E`
- Clip: `#EF4444`
- Primary text: `#E6EDF3`
- Secondary text: `#8B949E`

Critical operational states must use icon + text + shape/border + color. Browser limitations must not be communicated through disabled color alone.

## Copy requirements

Browser capability copy must be factual and short. Preferred semantic messages:

- `BROWSER AUDIO PERMISSION REQUIRED`
- `MIC / USB INPUT AVAILABLE`
- `TAB / WINDOW AUDIO AVAILABLE`
- `NO AUDIO TRACK RETURNED`
- `SYSTEM AUDIO NOT EXPOSED BY THIS BROWSER`
- `CAPTURE ENDED — RECONNECT SOURCE`
- `INSTALL LIVEMIXMASTER`
- `STORAGE LIMIT REACHED`

Generated artwork copy is illustrative until the Flutter implementation matches the repository-owned state names.

## Relationship to existing design pack

The existing Issue #1 Picsart pack remains the reference for shared desktop/mobile appearance, patchbay, recovery, settings/preflight, and compact monitoring. The Web folder adds only browser-specific release states and PWA artwork.
