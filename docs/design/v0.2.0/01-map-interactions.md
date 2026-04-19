# 01 — Map Interaction Spec

**Scope:** Every gesture the user can perform on the map canvas, the exact threshold that distinguishes gestures, what fires when, and what haptic + visual feedback accompanies it. This is the contract between user intent and the `AnnotationEngine`.

**Related:** [00 Design System](./00-design-system.md) (haptic table, motion tokens), [02 Annotation Sheet](./02-annotation-sheet.md) (what opens after selection).

## 1. Gesture map

Canvas has three primary gesture modes. The **active mode** is determined by the toolbar state, set via a single-segment toolbar at the bottom safe area:

| Mode | Toolbar selection | Dominant gesture |
|---|---|---|
| `browse` (default) | none highlighted | Pan, pinch, tap-to-select |
| `drop-pin` | Pin icon selected | Tap to drop a new pin |
| `draw-route` | Route icon selected | Tap to add vertex, double-tap to finish |
| `draw-polygon` | Polygon icon selected | Tap to add vertex, tap-on-first-vertex OR double-tap to close |

**Why mode switching (not gesture overloading).** Gesture overloading on the map (long-press = pin, drag = route, etc.) fails in the field with gloves and haste. Explicit mode gives a visible, discoverable, undoable commitment. Apple's Maps uses the same pattern for directions entry.

## 2. Gesture thresholds (authoritative)

All thresholds below are for `UIGestureRecognizer` configuration. iOS Engineer implements these as the **exact** numeric values — do not tune "by feel."

### 2.1 Tap (single-finger tap)

| Parameter | Value | Rationale |
|---|---|---|
| `numberOfTapsRequired` | 1 | — |
| `numberOfTouchesRequired` | 1 | — |
| Max translation before cancel | 10pt | Under 10pt movement = tap; 10pt+ = pan. Matches UIKit default `UITapGestureRecognizer` behavior |
| Max duration | 0.25s | Over 0.25s holding → promotes to long-press (see 2.3) |

**Outcome by mode:**
- `browse`: Nearest-neighbor query via R-tree within a 22pt radius in map-point space. If hit → select annotation → open sheet in read-mode. If no hit → deselect any selected annotation, no sheet.
- `drop-pin`: Drop a pin at tapped coordinate. Optimistic insert via `AnnotationEngine.insertPin(at:)`. Sheet opens in edit-mode. Medium haptic fires.
- `draw-route`: Append vertex to in-progress route. Selection haptic fires.
- `draw-polygon`: Same as route, plus check: if tap lands within 16pt of the first vertex, close the polygon.

### 2.2 Double tap

| Parameter | Value | Rationale |
|---|---|---|
| `numberOfTapsRequired` | 2 | — |
| Max inter-tap delay | 0.30s | System default |
| Max translation between taps | 12pt | — |

**Outcome by mode:**
- `browse`: Zoom in by 1 level, centered on tap point. Standard Apple Maps behavior; ship as-is.
- `drop-pin`: **ignored** (would otherwise drop two overlapping pins).
- `draw-route` / `draw-polygon`: **Finish gesture.** The double-tap does NOT add a vertex — the first tap is absorbed as a vertex-add, the second tap finalizes the route/polygon. Success haptic. Toolbar returns to `browse` mode. Sheet opens in edit-mode so user can title the route immediately.

**Edge case — accidental double-tap in draw modes.** If only 2 vertices exist and the user double-taps, we accept the finish and produce a 2-vertex route (valid: straight line). This is the documented behavior. To delete, use undo (not in v0.2.0; user swipes down on sheet and deletes through it).

### 2.3 Long press

| Parameter | Value | Rationale |
|---|---|---|
| `minimumPressDuration` | 0.35s | Fast enough to feel snappy; long enough to avoid accidental trigger during pan start |
| `allowableMovement` | 8pt | Stricter than system default (10pt) — long-press should feel planted |
| `numberOfTouchesRequired` | 1 | — |

**Outcome by mode:**
- `browse`: On threshold reached, **light** haptic fires (see 00 §5). If an annotation is underneath the press, the annotation enters **drag mode** — user can reposition it by continuing to hold and drag. If no annotation underneath, long-press is a no-op (no "quick-add" shortcut — modes only).
- `drop-pin`: same as `browse` drag on an existing pin — no "long-press to drop" shortcut. The explicit mode selection is the only path to drop.
- Other modes: ignored.

**Drag behavior (long-press on pin, then drag).**
- Visual: selected pin elevates — scale 1.15×, shadow radius 8pt, slight opacity on its coordinate ring (optional polish).
- Coordinate update: on drag-end, emit `AnnotationEngine.updateCoordinate(id:, to:)` → goes through CRDT LWW.
- Cancel: if user drags off-screen and back, the drag continues (follows finger).
- Drop-snap: no snap in v0.2.0. Coordinate is free-placed.
- Haptic: light on threshold, medium on drag-end (matches pin-drop haptic for symmetry).

### 2.4 Pan

Stock MapKit pan. No override. All drag interactions are handled by our own long-press-plus-drag recognizer, which must have `require(toFail:)` relationship with MapKit's built-in pan so that annotation-drag wins when a pin is underneath.

### 2.5 Pinch

Stock MapKit pinch. No override. Clustering reacts to zoom changes — see [05](./05-cluster-badge.md).

### 2.6 Rotate

Disabled in v0.2.0. `MKMapView.isRotateEnabled = false`. Rationale: collaborative spatial annotations are harder to reason about when orientation is ambiguous; users expect "up is north." Revisit in v0.3.

### 2.7 3D / pitch

Disabled in v0.2.0. `MKMapView.isPitchEnabled = false`. Same rationale.

## 3. Gesture resolution order

All recognizers attached to the `MKMapView` delegate's host view. Resolution:

```
1. Our tap            (requires 1 tap)
2. Our double-tap     (require(toFail: tap) — no, we want both distinct; tap has max duration 0.25s that hands off correctly)
3. Our long-press     (require(toFail: tap) — YES; otherwise tap fires at 0.25s duration before long-press at 0.35s)
4. MapKit's built-in pan
5. MapKit's built-in pinch
```

**Implementation note.** For steps 1–2, use one `UITapGestureRecognizer` with `numberOfTapsRequired = 1` and one with `= 2`, and set `singleTap.require(toFail: doubleTap)`. This is the standard pattern; double-tap gets priority, single-tap fires 300ms later if double is ruled out.

**Why this matters for UX.** If we don't set `require(toFail:)` correctly, a user double-tapping to zoom will drop a pin at their first tap AND zoom. That's a data-loss class bug disguised as a UX bug.

## 4. Mode switching UX

**Toolbar.** Bottom-safe-area-pinned, `surface.primary` background with 1pt `separator` top stroke. Four segmented items: Pin, Route, Polygon, Note. Selection is single-active. Height: 56pt + safe-area bottom inset.

**State transitions.**

| From | To | Trigger | Visual |
|---|---|---|---|
| `browse` | `drop-pin` | User taps Pin icon | Icon fills with `tint.action`, cursor-style ring appears on map center as affordance |
| `drop-pin` | `browse` | User drops a pin (sheet opens then dismissed) OR taps Pin icon again | Ring fades, icon deselects |
| `browse` | `draw-route` | User taps Route icon | Route icon fills; toolbar grows a "Finish" chip at trailing end (disabled until ≥2 vertices) |
| `draw-route` | `browse` | Double-tap finish OR user taps "Finish" chip OR taps Cancel (leading toolbar item) | Route finalized or discarded |
| `browse` | `draw-polygon` | User taps Polygon icon | Polygon icon fills; "Finish" chip appears |
| `draw-polygon` | `browse` | Close polygon by tap-on-first-vertex OR double-tap OR Finish chip | Polygon finalized |

**Escape routes.** In any draw mode, swiping down with two fingers on the map cancels the in-progress draw and returns to `browse` WITHOUT saving (safety valve). Confirm with light haptic.

**Mode indicator.** While in any non-browse mode, a compact pill appears at the **top** of the map canvas (below nav bar) reading e.g. `Dropping pin — tap to place`. Uses `type.footnote`, `surface.secondary` background, `radius.sm` corners. Accessible via VoiceOver as an announcement when mode changes.

## 5. Visual feedback per gesture

| Gesture + outcome | Visual |
|---|---|
| Tap-to-select pin | Pin scales to 1.2× over 120ms, returns to 1.0× over 120ms. Sheet opens. |
| Tap-in-empty during browse | 24pt ripple expands from tap point, 220ms `.easeOut`, `separator` color at 0.6 alpha. Feedback that the tap was received but nothing was selected. |
| Tap-to-drop pin | Pin drops from 16pt above final position, 180ms `.easeOut`, accompanied by medium haptic. Callout flashes "Pin added" for 1.2s in the mode indicator pill area. |
| Long-press reaches threshold | Pin scales to 1.15× with soft shadow. Light haptic. |
| Drag pin | Coordinate ring stays on pin; small label above pin shows live lat/long to 5 decimals in `type.caption`, `label.secondary`. |
| Route vertex added | Small `tint.action` circle (8pt) appears at vertex, polyline extends from last vertex. Selection haptic. |
| Polygon closed | Fill color animates from 0 → `annotation.polygon.fill` alpha over 200ms. Success haptic. |
| Deselect | If an annotation was selected, its scale returns to 1.0× and any halo fades 160ms. |

**Reduced Motion variant.** All scale/ripple animations become opacity-only (fade 120ms). Haptic unchanged. Mode indicator pill appears with no translation.

## 6. Acceptance criteria

For iOS Engineer to consider this spec "met":

- [ ] Tap threshold 10pt, long-press 0.35s + 8pt — verified in Xcode with `print` on recognizer callbacks during manual test
- [ ] Single-tap and double-tap correctly distinguish (single-tap fires 300ms after tap; double-tap fires immediately on second tap) — implemented via `require(toFail:)`
- [ ] In `drop-pin` mode, double-tap does **not** drop two pins (verified by visual + R-tree count)
- [ ] In `draw-route` mode, double-tap finalizes with the previous tap's vertex included (verified by polyline vertex count equals single-tap count — double-tap does not add its own vertex)
- [ ] Pin drag requires long-press-then-drag — no accidental drag during tap
- [ ] All 6 haptic events in [00 §5 haptic table](./00-design-system.md#5-motion--haptics) fire at the correct moment and are inhibited when System Haptics is off
- [ ] Rotate and pitch disabled on `MKMapView`
- [ ] Two-finger swipe-down escape works in draw modes and discards the in-progress route/polygon
- [ ] All gestures announce correctly under VoiceOver (see [06](./06-voiceover-tap-to-add-pin.md) for the golden-path script)
- [ ] Reduce Motion variant tested — no translations, only opacity changes
- [ ] All thresholds survive `swift test --filter MapInteractionTests` (test harness to be authored by iOS Engineer from this spec)

## 7. Out of scope for v0.2.0

- Undo / redo (separate v0.2.x ticket)
- Snap-to-road during route draw
- Geofence-triggered auto-pin
- Collaborative cursors (CloudKit sync off by default)
