# 03 — Empty States

**Scope:** Three distinct empty states users encounter in v0.2.0. Each has a specific cause, a specific remedy, and a specific visual treatment. Do not reuse one state to represent another — users must know exactly why nothing is on screen and what to do.

**Related:** [00 Design System](./00-design-system.md), [04 Offline Indicator](./04-offline-indicator.md).

## 1. The three empty states

| # | State | Cause | Primary remedy |
|---|---|---|---|
| A | **First-run empty project** | User just installed; zero annotations in the default project | Add first annotation |
| B | **Zero-annotation viewport** | Project has annotations, but none are in the currently visible map region | Zoom out OR navigate |
| C | **Offline-with-no-cache** | User is offline AND the visible tiles are not in the local tile cache | Go online OR pre-cache region |

These are **orthogonal** — the user can experience combinations (e.g., first-run + offline), and our rendering must handle all 8 combinations gracefully. See §5 for the combination matrix.

## 2. State A — First-run empty project

**Trigger.** `AnnotationEngine.count(project:) == 0` AND `hasSeenOnboarding == false` (or equivalent flag persisted in `UserDefaults` — bootstrap flag scoped to demo app).

**Visual.**

Placement: a **card** overlaid on the map, centered horizontally, vertically positioned so its bottom sits 32pt above the annotation toolbar. Card width: 340pt max, 88% of viewport width on smaller devices. Material: `.ultraThinMaterial` background for elegant overlay on top of map tiles.

```
┌─────────────────────────────────┐
│                                 │
│       ╭───────────╮             │
│       │    📍      │             │  ← SF Symbol "mappin.and.ellipse" at 56pt,
│       ╰───────────╯             │    tint.action
│                                 │
│      Your map is empty          │  ← type.sheetTitle, label.primary
│                                 │
│   Tap the pin icon below to     │  ← type.body, label.secondary, centered
│   drop your first annotation    │
│   anywhere on the map.          │
│                                 │
│   ┌───────────────────────┐     │
│   │    Show me how        │     │  ← primary button, filled, tint.action
│   └───────────────────────┘     │
│                                 │
│         Skip                    │  ← plain text button, label.secondary
│                                 │
└─────────────────────────────────┘
```

**Card padding.** `space.md` (16pt) all sides; `space.xl` (32pt) between icon and title; `space.md` between title and body; `space.lg` (24pt) between body and primary button; `space.sm` (8pt) between primary and Skip.

**Primary "Show me how" button.**
- Activates drop-pin mode (same as tapping the pin icon in the toolbar) and **dismisses the card**.
- After the card dismisses, the mode indicator pill at the top of the canvas reads `Tap anywhere to drop your first pin`.
- Does NOT force a pin drop at a fake location — user must choose where.

**"Skip" button.** Dismisses the card permanently (sets `hasSeenOnboarding = true`). Card does not reappear. User can re-trigger via Debug menu if needed.

**Persistence.** Card reappears on app relaunch if the project is still empty AND user hasn't tapped Skip or Show-me-how. If user tapped either and annotation count is still 0, no card — map canvas is "naked" and the annotation toolbar is the only affordance.

**Accessibility.**
- Card has `accessibilityViewIsModal = true` — map underneath is not accessible to VoiceOver while card is visible.
- Title + body read as a single element on first focus: `"Your map is empty. Tap the pin icon below to drop your first annotation anywhere on the map."`
- Primary button: `accessibilityLabel = "Show me how to add a pin"`, `accessibilityHint = "Enters pin-drop mode. You'll be asked to tap a location on the map."`
- Skip: `accessibilityLabel = "Skip and dismiss"`.

**Reduce Transparency.** Card becomes opaque `surface.secondary` — no material.

## 3. State B — Zero-annotation viewport

**Trigger.** `AnnotationEngine.count(project:) > 0` AND `RTree.search(boundingBox: currentViewport).isEmpty == true`.

**Philosophy.** The user has annotations elsewhere — they're just not looking at them. The UI must not alarm them; it must offer a clear path to where the data lives.

**Visual.**

Placement: a **compact pill** at the top of the map canvas (below nav bar + any mode indicator), centered horizontally. NOT a full card — that would over-dramatize a routine situation.

```
     ┌──────────────────────────────────────┐
     │ ↖  No annotations here · Show all    │
     └──────────────────────────────────────┘
```

- Pill height: 36pt. Padding: horizontal `space.md`, vertical `space.sm`. Background: `surface.secondary` with `radius.sm`. 1pt `separator` border.
- Leading: SF Symbol `arrow.up.left.and.arrow.down.right` (or `rectangle.dashed`) at `type.footnote` size, `label.secondary` tint. Conveys "look elsewhere / zoom out."
- Text: `No annotations here` in `type.footnote`, `label.primary`.
- Trailing: **Show all** — tappable, `tint.action` text. Fits map to a bounding box that contains all annotations in the project using `MKMapView.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(16,16,16,16), animated: true)`.

**Dismissal.** Pill auto-hides when an annotation enters the viewport (via pan/zoom). Reappears if the viewport is emptied again. No explicit close button — it's ambient state, not modal.

**Throttling.** To prevent flicker during aggressive panning, delay appearance by 250ms; delay dismissal by 100ms.

**Accessibility.**
- VoiceOver: announces once when the pill appears: `"No annotations in this area. Show all is available."` Uses `.announcement` posting; not screen-capture-worthy, but present in the a11y tree.
- Pill is a focusable element in VoiceOver tree; double-tap activates "Show all."

## 4. State C — Offline with no cache

**Trigger.** `NWPathMonitor` reports offline AND the currently visible tiles are all cache-misses (the `CachingTileOverlay` returns placeholder tiles for the entire visible rect).

**Philosophy.** This is the *specific* failure that Cartographer's value prop addresses. Users in the field rely on us to degrade gracefully. The UX must:
1. Acknowledge the problem without panic
2. Make the data the user *does* have (annotations) still usable
3. Offer a clear path to pre-cache next time

**Visual.**

**Tiles.** Empty tiles render as a subtle grey grid pattern, NOT pure grey. The grid is visual texture that says "here is where a map would be," not "nothing is here." Grid: 256pt squares (matches tile size) with 1pt `separator` @ 0.4 alpha cross-lines at tile corners. Background: `tertiarySystemBackground`.

**Annotations.** Render **on top of** the grid regardless of cache state. This is critical — the user's annotations are *their* data, and they must remain visible and interactive when tiles are missing. Route polylines and polygon overlays render normally; the grid becomes the canvas.

**Overlay card.** Placement: card at the top of the canvas (below nav bar), spanning full width minus `space.md` side inset. Height: auto. Material: `.ultraThinMaterial` over the grid. Dismissible via a small × on trailing, but also auto-dismisses when user connects or loads cached region.

```
┌─────────────────────────────────────────────────────┐
│ ⊘  You're offline and this area isn't cached.      │
│    Your pins are still here. Pan to cached areas    │
│    or connect to the internet to load tiles.        │
│                                                     │
│    [ Pre-cache this area next time → ]              │
└─────────────────────────────────────────────────────┘
```

- Leading icon: SF Symbol `wifi.slash` combined (top half) with `arrow.down.circle.dotted` (bottom half) — use a group — or simpler `wifi.exclamationmark` in `tint.warning`.
- Title copy in `type.body`, `label.primary`.
- Body copy in `type.footnote`, `label.secondary`, wraps.
- CTA: "Pre-cache this area next time" is an educational link. In v0.2.0 it opens a short bottom-sheet explaining region-download via the Debug menu (since v0.2.0 doesn't ship a full region-download UI). Post-v0.2.0: link to a proper Region Downloader screen.
- Close (×) at top-trailing: dismisses card for this session (not permanently).

**No tile retries.** Do not show a spinner in tile positions — it implies retry behavior we don't want. The tile engine's `loadTile(at:result:)` is documented as "placeholder on offline miss" (per CG-003 acceptance criteria). Honor that contract.

**Nav-bar offline indicator** is always visible when offline. Card is an additional, dismissible explainer for the specific case where the viewport is *also* uncached. See [04 Offline Indicator](./04-offline-indicator.md) for the always-on indicator.

**Accessibility.**
- VoiceOver on first appearance: `"Offline and map tiles for this area aren't cached. Your annotations are still available."`
- Pre-cache CTA: `accessibilityHint = "Opens instructions for caching a region before you go offline."`
- Grid pattern: the map itself carries an `accessibilityLabel = "Map area, tiles unavailable offline"` — so users who land focus on the empty canvas aren't confused.

## 5. Combination matrix

How the three empty-state affordances interact:

| First-run empty? | Zero viewport? | Offline no-cache? | What shows |
|---|---|---|---|
| Yes | n/a | No | **A** (first-run card); pill B suppressed |
| Yes | n/a | Yes | **A + C** stacked: A card (center) + offline card at top. Skip / Show-me-how still work. |
| No | Yes | No | **B** (pill) |
| No | Yes | Yes | **B + C**: pill + offline card. Pill appears below the card. |
| No | No | Yes | **C** only (offline card) |
| No | No | No | Nothing — normal state |

**Rule.** State A "wins" over state B because A is modal. State C is always additive because it's about a system-level condition, not a data-level one.

## 6. Accessibility specifics

- All overlay cards must set `accessibilityViewIsModal` per §2/§4 only when they are modal. State B pill is NOT modal.
- All state copy survives Dynamic Type AX3 without truncation. Copy is intentionally short to help.
- Offline-no-cache card's CTA is a full 44pt tap target even at default text size.
- Reduce Transparency: materials fall back to opaque `surface.secondary`.
- Reduce Motion: card appearances are opacity-only, no scale.

## 7. Dark-mode notes

- Grid in state C uses `separator` tokens which invert correctly.
- `ultraThinMaterial` uses system rendering; no manual adjustment.
- SF Symbol colors all resolve through semantic tints — automatic.
- Verify manually: offline card text remains 4.5:1 contrast against the tile grid in both light and dark. If a tile-less grid is used (our case), we're on `tertiarySystemBackground` — text on `surface.primary` via the material layer is fine.

## 8. Acceptance criteria

- [ ] State A card renders on first-run with `accessibilityViewIsModal`; dismissed by Show-me-how or Skip
- [ ] `hasSeenOnboarding` persists across relaunches; card reappears only when project is still empty AND flag unset
- [ ] State B pill appears after 250ms debounce when viewport is empty; dismisses after 100ms debounce on re-entry
- [ ] State B "Show all" correctly fits MKMapRect to the union of all annotation bounding boxes
- [ ] State C card appears only when offline AND tiles are cache-miss — verified via airplane-mode test on an uncached coordinate
- [ ] Annotations render on top of the grey grid in state C (critical correctness check)
- [ ] Combination matrix cases all tested: A+C, B+C, each individually
- [ ] Every state survives AX3 Dynamic Type without truncation
- [ ] Every state survives dark-mode (manual Xcode preview verification)
- [ ] VoiceOver announcements posted per §2/§3/§4
- [ ] Reduce Transparency: materials become opaque surfaces
- [ ] Reduce Motion: card appearances are opacity-only

## 9. Copy registry

Single source of truth for every string in empty states. iOS Engineer pulls these verbatim into `Localizable.strings` keyed as shown — do not edit copy without updating here first.

```
empty.first_run.title = "Your map is empty"
empty.first_run.body = "Tap the pin icon below to drop your first annotation anywhere on the map."
empty.first_run.primary_cta = "Show me how"
empty.first_run.skip = "Skip"

empty.viewport.text = "No annotations here"
empty.viewport.action = "Show all"

empty.offline_no_cache.title = "You're offline and this area isn't cached."
empty.offline_no_cache.body = "Your pins are still here. Pan to cached areas or connect to the internet to load tiles."
empty.offline_no_cache.cta = "Pre-cache this area next time"
```

## 10. Open questions for CTO

- **Onboarding scope.** Spec treats the first-run card as the entirety of v0.2.0 onboarding (per CHA-139 out-of-scope note). Confirm we are not expected to also include a multi-step tour, region-download walk-through, or demo-data seeder. If demo-data is desired, it lives in the Debug menu, not as an empty-state affordance.
- **Pre-cache CTA destination.** In v0.2.0 this points at a Debug-menu flow. Post-v0.2.0 we need a first-class Region Downloader screen — flag whether that lands as a follow-up ticket from this spec.
