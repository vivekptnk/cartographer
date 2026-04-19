# Cartographer v0.2.0 "Field Kit" — UX Pass

**Owner:** [Designer – Cartographer](/CHA/agents/designer-cartographer)
**Issue:** [CHA-139](/CHA/issues/CHA-139)
**Parent plan:** [CHA-123](/CHA/issues/CHA-123#document-plan)

## Purpose

Written, implementation-ready design specs for the v0.2.0 demo app. Every screen and interaction here is unambiguous enough that [iOS Engineer](/CHA/agents/ios-engineer-cartographer) can implement without design follow-up.

This folder is the **source of truth** for v0.2.0 UX. A Figma file is a rendered secondary artifact — if Figma and these specs disagree, these specs win until a spec revision is committed.

## Contents

| # | Doc | Scope |
|---|---|---|
| 00 | [design-system.md](./00-design-system.md) | Tokens, color roles, typography, spacing grid, motion, a11y baseline |
| 01 | [map-interactions.md](./01-map-interactions.md) | Tap / long-press / drag / pinch thresholds, haptic cues, route-finish gesture |
| 02 | [annotation-sheet.md](./02-annotation-sheet.md) | Pin / route / polygon / note layout, edit vs. read modes, delete confirmation |
| 03 | [empty-states.md](./03-empty-states.md) | First-run project, zero-annotation viewport, offline-with-no-cache |
| 04 | [offline-indicator.md](./04-offline-indicator.md) | Nav-bar cached-only vs. live pattern, no-layout-shift rules |
| 05 | [cluster-badge.md](./05-cluster-badge.md) | Count typography, WCAG AA contrast, zoom-12 break-apart behavior |
| 06 | [voiceover-tap-to-add-pin.md](./06-voiceover-tap-to-add-pin.md) | VoiceOver script for the golden-path tap-to-add-pin flow |

## Acceptance gate (per CHA-139 exit criteria)

- [x] Written acceptance criteria per screen — committed to this folder
- [x] Dark-mode + Dynamic Type variants specified in every doc
- [ ] VoiceOver script for tap-to-add-pin reviewed & approved by [CTO – Cartographer](/CHA/agents/cto-cartographer) — see `06-voiceover-tap-to-add-pin.md`
- [ ] Figma link + exports — **deferred**, flagged on [CHA-139](/CHA/issues/CHA-139). Written spec is the authoritative artifact; Figma will be produced as a visual companion once a designer with Figma tooling access picks it up. iOS Engineer is not blocked by Figma — written specs are sufficient.

## Design principles (ordered)

1. **Apple HIG first.** Deviate only with justification called out inline.
2. **Map is the canvas.** Chrome is earned. Every pixel of overlay must have a reason.
3. **Offline confidence.** Sync state must always be discoverable without being intrusive.
4. **Collaborative clarity.** When v0.2.x turns on CloudKit, attribution must already have a home.
5. **Progressive disclosure.** Defaults hide power-user features; long-press reveals them.
6. **Performance perception.** Pin-drop is optimistic; sync is visible in the nav bar, never blocking.

## Out of scope for v0.2.0 (per CHA-139)

- Marketing site, App Store screenshots
- Brand / icon / splash
- Onboarding flow (post-v0.2.0)
- Multi-project UI (one default project; debug menu switches)
- Live collaboration UI — protocol-ready but CloudKit sync is toggled off by default in v0.2.0

## Review loop

All specs return to [CTO – Cartographer](/CHA/agents/cto-cartographer) for approval. VoiceOver script requires explicit sign-off per CHA-139 exit criteria.
