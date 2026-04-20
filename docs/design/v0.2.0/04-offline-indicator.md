# 04 — Offline-Mode Indicator

**Scope:** The always-visible connectivity status indicator in the navigation bar. Its states, transitions, copy, and the no-layout-shift constraint that distinguishes Cartographer's treatment from the "alarmist banner" pattern common in consumer apps.

**Related:** [00 Design System](./00-design-system.md), [03 Empty States §4 (offline-no-cache)](./03-empty-states.md#4-state-c--offline-with-no-cache).

## 1. Philosophy

Cartographer is **offline-first**. Offline is not an error state; it is the happy path for our target users. The indicator must:

1. Always be **visible** — users in the field never have to dig for it.
2. Be **ambient**, not **alarming** — a small glyph + optional text, never a full-width banner that shifts layout.
3. **Never cause layout shift** when state changes. Tiles, pins, sheets, and nav-bar siblings must remain pixel-stable as `live ↔ cached-only ↔ offline-no-cache` transitions happen.
4. Carry sync status when sync is enabled (v0.2.x) without redesign — the slot must generalize.

## 2. Placement

The indicator lives in the **navigation bar trailing area**, as a compact view. Specifically, a custom `UIBarButtonItem` with a `customView` anchored in the nav bar.

```
┌──────────────────────────────────────────┐
│  ←      Default Project       [◉ Live]   │  ← nav bar
├──────────────────────────────────────────┤
│                                          │
│         <MAP CANVAS>                     │
│                                          │
└──────────────────────────────────────────┘
```

**Why trailing, not a separate bar.** A separate bar at the top creates layout shift when shown/hidden. Living inside the nav bar means the indicator occupies a fixed slot whether or not the state is "notable."

**Width reservation.** The slot is a **fixed 88pt** view. Every state below must render within that width. This is the no-layout-shift contract: state A and state B must be the same width, even if state A is "Live" and state B is "Offline."

**Tappable.** The view is a button; tapping it opens a detail popover (§5).

## 3. States

All four states share the slot. Transitions cross-fade in 200ms (see [00 §5](./00-design-system.md#5-motion--haptics)) with NO translation — `UIView.transition(with:..., options: .transitionCrossDissolve)`.

### 3.1 `live` (online, reachable)

| Element | Value |
|---|---|
| Dot | 8pt filled circle, `tint.success` (systemGreen) |
| Label | "Live" |
| Label style | `type.footnote`, `label.primary` |
| Icon | (none — the dot is the icon) |

Appearance:
```
┌────────────────┐
│ ●  Live        │
└────────────────┘
```

### 3.2 `cached-only` (online, but tile source is unreachable for THIS region — rare; e.g., remote tile server 500s for this area, but the network itself is up)

| Element | Value |
|---|---|
| Icon | SF Symbol `arrow.down.circle.dotted` |
| Label | "Cached" |
| Label style | `type.footnote`, `label.secondary` |
| Icon tint | `label.secondary` |

Appearance:
```
┌────────────────┐
│ ⬇  Cached      │
└────────────────┘
```

### 3.3 `offline` (no connectivity — airplane mode, out-of-range, etc.)

| Element | Value |
|---|---|
| Icon | SF Symbol `wifi.slash` |
| Label | "Offline" |
| Label style | `type.footnote`, `label.secondary` |
| Icon tint | `tint.warning` (systemOrange) |

Appearance:
```
┌────────────────┐
│ ⊘  Offline     │
└────────────────┘
```

### 3.4 `syncing` (sync enabled, op-log push/pull in progress — v0.2.x when CloudKit sync toggled on; v0.2.0 never renders this)

| Element | Value |
|---|---|
| Icon | SF Symbol `arrow.triangle.2.circlepath`, rotating 360° over 1.4s, linear, infinite |
| Label | "Syncing" |
| Label style | `type.footnote`, `label.primary` |
| Icon tint | `tint.action` |

On sync complete, transition to `live` via a 600ms flash: icon swaps to `checkmark.circle.fill` in `tint.success`, label briefly reads `"Synced"`, then cross-fades to `live`.

On sync error: icon becomes `exclamationmark.triangle.fill` in `tint.warning`, label `"Sync paused"`. Tap opens detail popover with retry. Error haptic once per session (see [00 §5](./00-design-system.md#5-motion--haptics)).

## 4. No-layout-shift rules

Absolute rules. Any violation is a bug.

1. **Slot width is fixed at 88pt.** If a future state is wider, we shorten the label first. "Offline" is our upper bound for v0.2.0. Test: measure in Xcode snapshot that every state's intrinsic content size fits ≤ 88pt wide at default Dynamic Type and at AX3 (fallback: label truncates with ellipsis rather than expanding the slot).
2. **Dot/icon column is fixed at 14pt wide.** All state glyphs fit in 14pt × 14pt. SF Symbol `configuration: .init(pointSize: 12, weight: .semibold)`.
3. **Gap between glyph and label is 6pt** (matches `space.xs + 2pt` eyeball but it's 6pt because it's a fine-visual gap, not an 8pt-grid element).
4. **Label uses `type.footnote` at all times.** Even under AX3 Dynamic Type, the indicator label does NOT scale. Rationale: it's a status glyph, not primary content. VoiceOver + popover (§5) carry the semantic content at any text size.
5. **No shadow, no border on the container.** Shadow changes effective occupied area; border changes rendered metrics. Neither belongs here.
6. **Transitions are opacity-only.** No scale, no translation. `UIView.transition(..., options: [.transitionCrossDissolve])` exclusively.

**Verification.** iOS Engineer runs a snapshot test that captures the nav bar in each of the four states and asserts pixel-identical layout for every view sibling in the nav bar (title, back button, etc.).

## 5. Detail popover (tap behavior)

Tapping the indicator opens a small **popover** anchored to the indicator view. Contents vary by state.

### 5.1 `live`

```
┌──────────────────────────────────┐
│   ● Live                         │
│                                  │
│   Connected to tile source.      │
│   All tiles load remotely when   │
│   not in cache.                  │
│                                  │
│   Sync: Off in v0.2.0 demo.      │  ← only if sync disabled
│   [ Enable sync ]                │
└──────────────────────────────────┘
```

### 5.2 `cached-only`

```
┌──────────────────────────────────┐
│   ⬇ Cached tiles only            │
│                                  │
│   Tile source is unreachable,    │
│   but your device is online.     │
│   Showing the last-cached tiles. │
│                                  │
│   [ Retry tile source ]          │
└──────────────────────────────────┘
```

### 5.3 `offline`

```
┌──────────────────────────────────┐
│   ⊘ Offline                      │
│                                  │
│   No internet connection.        │
│   Cartographer is designed for   │
│   this — pan to cached areas     │
│   to keep working.               │
│                                  │
│   Cache status:                  │
│     • 128 MB of tiles cached     │
│     • Last updated 2 hours ago   │
│                                  │
│   [ Pre-cache a region ]         │
└──────────────────────────────────┘
```

### 5.4 `syncing` / sync paused

Standard progress info + retry button. Design lives with v0.2.x sync work — out of scope for v0.2.0 but the slot generalizes.

**Popover sizing.** 280pt wide, auto height. `UIPopoverPresentationController` on iPhone falls back to `.pageSheet` with `.medium` detent below iPad — acceptable.

**Popover dismissal.** Tap outside dismisses. Tap indicator again also dismisses (toggle).

## 6. State detection rules

Informative for iOS Engineer — drives when the indicator transitions.

| From → to | Trigger |
|---|---|
| → `live` | `NWPathMonitor` reports `.satisfied` AND tile source returned a 200 on the most recent request |
| → `cached-only` | `NWPathMonitor` reports `.satisfied` AND the last N (= 3) tile requests all failed with network errors OR 5xx |
| → `offline` | `NWPathMonitor` reports `.unsatisfied` OR `.requiresConnection` |
| → `syncing` | `SyncEngine.state == .pushing` OR `.pulling` |
| → `syncing` completion | `SyncEngine.state == .idle` — then flash `.synced` for 600ms then settle on whatever connectivity state currently is |

Debounce: hold a state for at least 500ms before transitioning (prevents flicker on bad networks).

## 7. Accessibility

- **VoiceOver label.** Concatenates the icon meaning and the label: e.g. `"Connected. Live."` / `"Offline."` / `"Only cached tiles available."` / `"Sync in progress."`
- **VoiceOver value.** For `offline`, value carries cache info: `"128 megabytes cached."`
- **Hint.** `"Double-tap for details."`
- **Announcement on state change.** State changes post a `.announcement` so VoiceOver users learn about transitions without forcing focus.
- **Dynamic Type.** Label itself doesn't scale per §4 rule 4, but the detail popover inside scales fully through AX3.
- **Reduce Motion.** Syncing spinner swaps to a slow opacity pulse (100% → 40% → 100% over 1.6s) instead of rotation. `.synced` flash becomes an opacity fade with no icon swap — checkmark still appears; the motion of the swap is dissolve-only.

## 8. Dark-mode notes

- All colors resolve through system semantics (`systemGreen`, `systemOrange`, `label`, `secondaryLabel`) — automatic.
- Verify contrast: `systemGreen` dot on dark nav bar background is at 3:1 minimum; Apple guarantees this. `systemOrange` icon on dark: 3.5:1 — OK for UI. Test with Xcode Accessibility Inspector in dark appearance.

## 9. Acceptance criteria

- [ ] Fixed 88pt slot width at all times
- [ ] Cross-fade transitions between states (200ms opacity, no translation, no scale)
- [ ] Four states render correctly: live, cached-only, offline, syncing
- [ ] State derived from `NWPathMonitor` + tile source health + sync engine state per §6
- [ ] 500ms debounce before transitioning
- [ ] Tap opens popover with state-specific detail
- [ ] Label does not scale under Dynamic Type (AX3 check — remains `.footnote`)
- [ ] Popover content DOES scale with Dynamic Type
- [ ] VoiceOver announces state changes via `UIAccessibility.post(notification: .announcement, argument:)`
- [ ] Error haptic fires once per session on first sync failure only (not on every subsequent)
- [ ] Snapshot test verifies no layout shift in sibling nav-bar elements across all state transitions
- [ ] Dark-mode verified in both Xcode preview and manually on device
- [ ] Reduce Motion: sync spinner becomes opacity pulse; state transitions still work

## 10. Copy registry

```
offline.label.live = "Live"
offline.label.cached = "Cached"
offline.label.offline = "Offline"
offline.label.syncing = "Syncing"
offline.label.synced_flash = "Synced"
offline.label.sync_paused = "Sync paused"

offline.popover.live.title = "Live"
offline.popover.live.body = "Connected to tile source. All tiles load remotely when not in cache."
offline.popover.cached.title = "Cached tiles only"
offline.popover.cached.body = "Tile source is unreachable, but your device is online. Showing the last-cached tiles."
offline.popover.cached.cta = "Retry tile source"
offline.popover.offline.title = "Offline"
offline.popover.offline.body = "No internet connection. Cartographer is designed for this — pan to cached areas to keep working."
offline.popover.offline.cache_status_header = "Cache status"
offline.popover.offline.cache_status_size_format = "%@ of tiles cached"
offline.popover.offline.cache_status_updated_format = "Last updated %@"
offline.popover.offline.cta = "Pre-cache a region"
```

## 11. Open questions for CTO

- **Cached-only detection.** We rely on "last 3 tile requests failed" heuristic. Confirm this maps reasonably onto the current `CachingTileOverlay` implementation, or request a different signal (e.g. explicit `tileSource.isReachable` property).
- **Cache status in popover.** Size in MB and last-updated are displayed. Both require lightweight queries on `TileCache` (total size, max `last_accessed`). Is this within the `TileCache` actor's public API? If not, flag a small additional method request against CG-002.
- **Live-state copy.** "Live" could read as hype-y. Alternative: "Online." I prefer "Live" because it pairs well with "Cached" and "Offline" — three distinct, short, equal-weight words. Confirm.
