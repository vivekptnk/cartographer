# 00 — Design System Baseline

**Scope:** Tokens shared across every v0.2.0 screen. Nothing in specs 01–06 should invent a color, type style, or spacing value not defined here.

## 1. Color roles

All colors are **system semantic colors** (UIColor / SwiftUI `Color`) — no custom palette in v0.2.0. This guarantees dark-mode, high-contrast, and Accessibility Inspector behavior come for free.

| Role | Light | Dark | Usage |
|---|---|---|---|
| `surface.primary` | `systemBackground` | `systemBackground` | Sheet background, nav bar |
| `surface.secondary` | `secondarySystemBackground` | `secondarySystemBackground` | Empty-state card, grouped rows |
| `surface.tertiary` | `tertiarySystemBackground` | `tertiarySystemBackground` | Field input well, disabled chip |
| `label.primary` | `label` | `label` | Body + title text |
| `label.secondary` | `secondaryLabel` | `secondaryLabel` | Captions, metadata, coordinates |
| `label.tertiary` | `tertiaryLabel` | `tertiaryLabel` | Placeholder text only |
| `separator` | `separator` | `separator` | Row dividers, field underlines |
| `tint.action` | `systemBlue` | `systemBlue` | Primary buttons, links, active nav icons |
| `tint.destructive` | `systemRed` | `systemRed` | Delete actions, error banners |
| `tint.warning` | `systemOrange` | `systemOrange` | Offline-no-cache indicator dot |
| `tint.success` | `systemGreen` | `systemGreen` | Sync-complete flash |
| `annotation.pin` | `systemRed` | `systemRed` | Default pin fill |
| `annotation.route` | `systemBlue` | `systemBlue` | Route polyline stroke |
| `annotation.polygon.stroke` | `systemPurple` | `systemPurple` | Polygon outline |
| `annotation.polygon.fill` | `systemPurple @ 0.18 alpha` | `systemPurple @ 0.25 alpha` | Polygon fill |
| `annotation.note` | `systemYellow` | `systemYellow` | Note pin variant |
| `cluster.badge.fill` | `systemBlue` | `systemBlue` | Cluster circle background |
| `cluster.badge.label` | `white` | `white` | Cluster count text (contrast-locked, see 05) |

**Rule.** When MapKit rasterizes annotations, pass system color tokens into `UIColor(...)` at draw time — do not resolve to RGB at layout time. Dark-mode transitions then happen automatically when the user toggles Dark Appearance from Control Center.

## 2. Typography

All text uses **SF Pro via `UIFont.preferredFont(forTextStyle:)` / SwiftUI `.font(.body)` etc.** to inherit Dynamic Type.

| Token | Apple style | Weight | Usage |
|---|---|---|---|
| `type.navTitle` | `.headline` | semibold | Nav bar title — project name |
| `type.sheetTitle` | `.title3` | semibold | Annotation sheet title field |
| `type.body` | `.body` | regular | Notes, descriptions |
| `type.caption` | `.caption` | regular | Coordinates, timestamp, attribution |
| `type.footnote` | `.footnote` | regular | Offline-mode indicator text |
| `type.cluster` | `.headline` | semibold, **monospaced-digit** | Cluster count badge — must use `.monospacedDigit()` so `10 → 11` doesn't jitter |
| `type.button.primary` | `.body` | semibold | Primary CTA on empty states |
| `type.button.destructive` | `.body` | semibold | "Delete pin" confirmation |

**Dynamic Type.** Every screen must pass visual inspection at `AX1` (larger) and `AX3` (largest accessibility). The annotation sheet (02) and empty states (03) must **not** truncate title or CTA at `AX3` — tested on iPhone SE (3rd gen) 4.7" physical width as the tightest-viable device.

**Accessibility escape hatch.** Cluster badge (05) **does not** scale with Dynamic Type — map overlays stay visually stable. Instead, badges expose a VoiceOver label; very-large-text users get count via rotor, not overlay glyph.

## 3. Spacing & grid

**8pt grid.** All margins, paddings, and component gaps are multiples of 4pt, with 8pt as the default unit. Acceptable values: `4, 8, 12, 16, 20, 24, 32, 48`.

| Token | pt | Usage |
|---|---|---|
| `space.xs` | 4 | Icon-to-label gap inside a chip |
| `space.sm` | 8 | Row internal padding |
| `space.md` | 16 | Sheet edge padding, standard gutter |
| `space.lg` | 24 | Sheet section separation |
| `space.xl` | 32 | Empty-state headline-to-copy gap |
| `space.xxl` | 48 | Empty-state illustration-to-copy gap |

**Corner radius.**

| Token | pt | Usage |
|---|---|---|
| `radius.sm` | 8 | Chips, offline indicator pill |
| `radius.md` | 12 | Field inputs, secondary buttons |
| `radius.lg` | 16 | Sheet top corners (detent transitions clip correctly), empty-state cards |
| `radius.circle` | ½ × diameter | Cluster badge, pin dot |

**Sheet detents.** Annotation sheet uses `.medium` (≈ 50%) and `.large` detents. Read-mode opens at `.medium`; edit-mode promotes to `.large` automatically when the keyboard appears.

## 4. Iconography

**SF Symbols only** in v0.2.0. No custom glyphs. Size: `.title3` for nav-bar symbols, `.body` for inline. Weight: `.regular` default, `.semibold` when selected.

| Concept | Symbol | Notes |
|---|---|---|
| Add pin | `mappin.and.ellipse` | Nav-bar trailing (while in drop-mode) |
| Route | `point.topleft.down.to.point.bottomright.curvepath` | Toolbar |
| Polygon | `skew` | Toolbar |
| Note | `note.text` | Toolbar |
| Offline | `wifi.slash` | Nav-bar offline indicator (see 04) |
| Cached-only | `arrow.down.circle.dotted` | Nav-bar indicator |
| Sync in progress | `arrow.triangle.2.circlepath` | Animated rotate, nav-bar |
| Sync complete | `checkmark.circle.fill` | 600ms flash then hide |
| Sync error | `exclamationmark.triangle.fill` | Nav-bar, tappable to see detail |
| Delete | `trash` | Destructive actions |
| Share / export | `square.and.arrow.up` | Standard system share |

## 5. Motion & haptics

**Motion.**
- Default curve: `UIView.AnimationCurve.easeInOut` / SwiftUI `.easeInOut(duration: 0.22)`
- Sheet transitions: system defaults — do not override
- Cluster break-apart at zoom threshold: 180ms `.easeOut`, pins radiate outward from cluster centroid
- Offline-indicator state swap: **cross-fade 200ms**, no translation (prevents layout shift — see 04)

**Reduced Motion.** Honor `UIAccessibility.isReduceMotionEnabled`. When true:
- Cluster break-apart: no radial animation; pins appear in place (opacity fade only)
- Pin-drop haptic still fires; visual pin scale-bounce is disabled (static opacity fade-in)
- Sync spinner swaps to a static dot that pulses opacity only

**Haptics (CoreHaptics / `UIImpactFeedbackGenerator`).** Bound to intentional user actions only. Never during idle state changes (never haptic on incoming sync deltas — that's annoying in the field).

| Event | Generator | Intensity |
|---|---|---|
| Pin drop (tap confirms) | `UIImpactFeedbackGenerator(.medium)` | — |
| Long-press reaches threshold (ready to drag / route start) | `UIImpactFeedbackGenerator(.light)` | — |
| Route vertex added (each tap during route draw) | `UISelectionFeedbackGenerator` | — |
| Route finished (double-tap) | `UINotificationFeedbackGenerator(.success)` | — |
| Delete confirmed | `UINotificationFeedbackGenerator(.warning)` | — |
| Cluster break-apart crossing zoom 12 | **none** — gesture is passive pinch/scroll, no haptic |
| Sync error (first occurrence per session) | `UINotificationFeedbackGenerator(.error)` | — |

**Rule.** If the user has `System Settings → Sounds & Haptics → System Haptics` off, we silently no-op. Never fall back to sound for the same event.

## 6. Accessibility baseline

Non-negotiable for v0.2.0:

- **VoiceOver:** every annotation view, every nav-bar control, every sheet field carries `accessibilityLabel` + `accessibilityHint` + `accessibilityValue` where state exists. Pin example: label `"Pin"`, value `"Summit cairn"`, hint `"Double-tap to open details, swipe up with one finger for actions"`.
- **Dynamic Type:** scale to `AX3` without truncation in sheets and empty states (cluster badge is the documented exception).
- **Contrast:** WCAG 2.1 AA minimum — text contrast ≥ 4.5:1 for body, ≥ 3:1 for large/UI. Cluster badge tested against light and dark OSM tiles (see 05).
- **Hit targets:** minimum 44×44 pt per Apple HIG. Pin visual dot can be smaller (24pt) only if surrounded by a 44pt invisible tap area; R-tree nearest-neighbor then resolves.
- **Reduce Motion:** honored per section 5.
- **Reduce Transparency:** honored — sheet backgrounds swap from material to opaque `systemBackground`.
- **Differentiate Without Color:** never rely on color alone. Route vs. polygon differentiated by stroke style + SF Symbol label in legend, not just hue.
- **VoiceOver map rotor:** the map view exposes a custom rotor `"Annotations"` that cycles visible annotations in distance-from-center order. Implementation note for iOS Engineer: `accessibilityCustomRotors` on the `MKMapView`.

## 7. Device targets

- **Smallest supported:** iPhone SE (3rd gen) — 375pt × 667pt @ 2x — all layouts must work here.
- **Reference device for screenshots:** iPhone 15 — 393pt × 852pt @ 3x.
- **Largest:** iPhone 15 Pro Max — 430pt × 932pt @ 3x. Map canvas gains width; sheet stays centered at max 640pt width (no stretching).
- **Orientation:** portrait and landscape both supported. Nav bar collapses to compact in landscape; sheet becomes `.medium` → `.large` detents still work.
- **iPad / macOS:** not a v0.2.0 target. Specs assume iPhone.

## 8. Implementation checklist for iOS Engineer

When implementing any v0.2.0 screen:

- [ ] Colors resolved via `UIColor.<semantic>` / `Color.<semantic>`, never hex
- [ ] Fonts resolved via `preferredFont(forTextStyle:)` / `.font(.body)`, never fixed-pt
- [ ] Spacing matches token table in section 3
- [ ] SF Symbols only (section 4)
- [ ] Haptics match section 5 event table exactly
- [ ] Every interactive element has VoiceOver label + hint
- [ ] Reduce Motion, Reduce Transparency, Increase Contrast branches implemented
- [ ] 44×44pt hit targets verified with Accessibility Inspector
- [ ] AX3 Dynamic Type verified on iPhone SE
- [ ] Light + Dark appearance both verified via Xcode preview variants
