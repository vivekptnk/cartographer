# 02 — Annotation Sheet

**Scope:** The modal sheet that appears when the user selects an existing annotation (read-mode) or creates a new one (edit-mode). Covers all four annotation types: pin, route, polygon, note. Defines the destructive-delete confirmation pattern.

**Related:** [00 Design System](./00-design-system.md), [01 Map Interactions](./01-map-interactions.md).

## 1. Presentation

**Container.** `UISheetPresentationController` with `.medium` and `.large` detents. Prefer `UIViewController` embedded in SwiftUI via `.sheet` + `.presentationDetents([.medium, .large])` for SwiftUI code path (this is a v0.2.0 MapCoordinator concern).

| State | Default detent | Behavior |
|---|---|---|
| Read-mode | `.medium` | User can swipe up to `.large` to see full notes / attribution |
| Edit-mode (keyboard visible) | `.large` | Auto-promote when `keyboardWillShow`; no animation jank because detent change is the system default animation |
| Edit-mode (keyboard hidden) | `.medium` | Matches read-mode height so switching modes doesn't resize |

**Grabber.** `preferredGrabberVisible = true` in read-mode. Hidden in edit-mode to signal "you're editing, commit or cancel."

**Dismissal.**
- Read-mode: swipe-to-dismiss enabled. Tapping the map outside the sheet also dismisses.
- Edit-mode with **unsaved changes**: swipe-to-dismiss triggers a confirmation action sheet (see §4). Without unsaved changes, dismiss freely.

**Backdrop.** `.largestUndimmedDetentIdentifier = .medium` — in read-mode the map stays fully visible and pannable behind the sheet. Confirmed Apple HIG pattern (Maps directions, Weather).

## 2. Shared sheet anatomy

All four annotation types share this skeleton:

```
┌─────────────────────────────────┐
│   [grabber]                     │  ← read-mode only
│                                 │
│   [Cancel]    Title    [Save]   │  ← toolbar, edit-mode only
│                                 │
│   ─────────────────────────     │  ← separator
│                                 │
│   Title field / title text      │  type.sheetTitle
│   Type label                    │  type.caption, label.secondary
│                                 │
│   Body field / body text        │  type.body
│                                 │
│   Metadata section              │  type.caption, label.secondary
│   ├─ Coordinate(s)              │
│   ├─ Created <timestamp>        │
│   └─ Attribution (when sync on) │
│                                 │
│   [Action buttons]              │  read-mode only — see §3
│                                 │
└─────────────────────────────────┘
```

Edge padding: `space.md` (16pt) horizontal, `space.md` top & bottom. Section gap: `space.lg` (24pt).

## 3. Read-mode vs. edit-mode

**Read-mode** (user tapped an existing annotation):
- Toolbar: hidden. Navigation bar with grabber only.
- Title: rendered as text (`type.sheetTitle`, `label.primary`).
- Body: rendered as text (`type.body`, `label.primary`). Multi-line, wraps freely.
- Action row at the bottom of content area: **Edit** (leading, tint) and **Delete** (trailing, `tint.destructive`). Both buttons full-width in a horizontal stack with `space.sm` gap. Secondary actions: **Share** (SF Symbol `square.and.arrow.up` in the top-trailing nav area).
- Tapping Edit swaps to edit-mode. Tapping Delete fires the destructive-delete confirmation — see §4.

**Edit-mode** (new annotation OR Edit tapped):
- Toolbar: visible, hosts **Cancel** (leading) and **Save** (trailing). Title centered in toolbar reads `New Pin` / `New Route` / `New Polygon` / `New Note` (new), or `Edit Pin` / etc. (existing).
- Title: `UITextField` / SwiftUI `TextField`, placeholder text `Name this <type>` in `label.tertiary`. First-responder on open for new annotations; not first-responder when editing existing (user must tap to focus to prevent accidental edit).
- Body: `UITextView` / SwiftUI `TextEditor`, placeholder `Notes, coordinates, or details`. Expands up to 8 lines then scrolls internally.
- Metadata: read-only even in edit-mode. Coordinate is editable for pins only (see type-specific section below).
- **Save enablement:** Save is enabled when title is non-empty OR body is non-empty. An annotation with no text content is allowed (the coordinate alone is the data), but we prompt the user: if they tap Save with an empty title, the title auto-fills to a default (see §5).

## 4. Destructive delete — confirmation pattern

**Trigger.** The **Delete** button in read-mode.

**Pattern.** Use a `UIAlertController` with `.actionSheet` style (renders as a sheet on iPhone — correct HIG for iPhone confirmation of destructive actions).

```
┌─────────────────────────────────┐
│                                 │
│      Delete "<title>"?          │
│                                 │
│   This can't be undone in       │
│   v0.2.0.                       │
│                                 │
├─────────────────────────────────┤
│        Delete                   │  ← destructive, tint.destructive
├─────────────────────────────────┤
│        Cancel                   │  ← default, tint.action
└─────────────────────────────────┘
```

**Why include the title in the prompt.** Users often have multiple pins near each other; seeing the title in the dialog rules out tap-misses.

**Behavior.**
- Tap Delete: emit `AnnotationEngine.delete(id:)` (this writes a CRDT tombstone via OR-Set). Warning haptic. Sheet dismisses. Annotation disappears from map with a 180ms opacity fade (Reduce Motion: instant).
- Tap Cancel: dismiss the alert only; the sheet stays in read-mode.

**Non-destructive alternative not offered in v0.2.0.** We do not offer an "Archive" path. Delete is the only verb. If users ask for recovery, we explain via release notes that v0.3 will add trash.

**Accessibility.** Delete button has `accessibilityHint = "Permanently removes this pin. Activates a confirmation."` VoiceOver reads title + Delete + Cancel in the alert.

## 5. Type-specific layouts

### 5.1 Pin

**Read-mode:**
- Icon + type label: red dot (`annotation.pin`) + `Pin`.
- Coordinate: `37.7749° N, 122.4194° W` rendered in `type.caption`, `label.secondary`. `.monospacedDigit()` on the number so copy-paste aligns.
- "Copy coordinate" action appears as a long-press context menu on the coordinate row.

**Edit-mode:**
- Coordinate is editable via a disclosure row: `Coordinate › <lat, lon>`. Tapping presents a sub-sheet with two `.decimalPad` text fields. This is present but secondary; most users will reposition by dragging the pin on the map (see [01 §2.3 drag behavior](./01-map-interactions.md#23-long-press)).

**Default title on Save-with-empty.** `Pin @ <HH:mm>` (user's locale).

**Icon selection.** Deferred to v0.3. All pins in v0.2.0 render with the default SF Symbol `mappin.circle.fill` and `annotation.pin` color. Exception: a pin whose `type` metadata is `.note` uses `annotation.note` color and `note.text` overlay.

### 5.2 Route

**Read-mode:**
- Icon + type label: polyline swatch (`annotation.route` stroke, 3pt) + `Route`.
- Stats row (3 columns): **Distance** | **Vertices** | **Duration** (duration blank in v0.2.0 — no timestamped recording path; slot shows `—`).
- Coordinate: "from–to" summary — first and last vertex lat/lon in `type.caption`. Full vertex list hidden behind a `Show all <N>` disclosure.

**Edit-mode:**
- Vertex list view appears below body, scrollable. Each row: index, coordinate, trailing "•••" context menu (`Remove vertex`).
- "Reverse direction" button below the list, secondary tint.
- Coordinate fields are read-only here — route vertex editing is a v0.3 affordance. The current edit flow is **redraw** (delete → recreate). Document this in tooltip + acceptance criteria.

**Default title on Save-with-empty.** `Route · <N> points · <length>` (`0.43 km` in metric, `0.27 mi` imperial — follow device `Locale.current`).

### 5.3 Polygon

**Read-mode:**
- Icon + type label: polygon swatch (`annotation.polygon.stroke` 1.5pt border, fill at alpha) + `Polygon`.
- Stats: **Area** (auto-computed using spherical earth approximation — CLLocationManager distance formulas suffice at MKMapRect scale) | **Perimeter** | **Vertices**.
- Coordinate summary: centroid lat/lon.

**Edit-mode:**
- Vertex list like route. No direction concept.
- Closed/open indicator is read-only; all polygons in v0.2.0 are auto-closed on creation.

**Default title on Save-with-empty.** `Polygon · <area>`.

### 5.4 Note

A note is conceptually a pin with emphasis on body text. Visually differentiated to help users who use pins for places and notes for journaling.

**Read-mode:**
- Icon + type label: yellow dot (`annotation.note`) + `Note`.
- Body is the primary content — render body at default `type.body` but give it more vertical space (min 6 lines visible before scroll).
- Coordinate shown in `type.caption` at the bottom of the metadata section.

**Edit-mode:**
- Body field auto-focuses (title is optional; body is primary).

**Default title on Save-with-empty.** First 32 characters of body, trimmed. If body is also empty, fallback to `Note @ <HH:mm>`.

## 6. States table

| State | Trigger | Visual |
|---|---|---|
| `loading` | Sheet opens for an annotation whose full data is being read from SQLite | Title placeholder shimmer for 1 frame (< 16ms expected — materialization is fast). If > 200ms, show `ProgressView()` centered. |
| `idle-read` | Loaded, read-mode | Content visible, action row at bottom |
| `idle-edit` | Edit-mode, no unsaved changes | Cancel disabled-tint OR enabled (dismiss without save); Save disabled if both title and body unchanged from loaded state |
| `dirty-edit` | Edit-mode, unsaved changes | Cancel enabled (shows "Discard changes?" action sheet on tap); Save enabled |
| `saving` | User tapped Save | Save button shows `ProgressView()`; fields disabled. Expected < 50ms for op-log append. |
| `error-save` | Op-log append failed (unlikely with SQLite) | Inline banner below title: red with `tint.destructive`, "Couldn't save — try again". Save re-enabled. |
| `syncing-attribution` | CloudKit fetch in progress (v0.2.x when sync on) | Attribution row shows `ProgressView()` next to "Checking who edited this" |
| `offline-read` | Viewing an annotation that was last edited on another device, not yet pulled from CloudKit | Attribution row shows "Last edited locally" without attempting remote fetch. No error. |
| `empty` | N/A — sheet is not shown for empty state. Empty state lives on the map canvas — see [03](./03-empty-states.md). | — |

## 7. Accessibility

- **Modal focus.** When sheet opens, VoiceOver focus moves to the title field (edit-mode) or the title text (read-mode). `accessibilityViewIsModal = true` on the sheet's root view so VoiceOver cannot escape to the map underneath.
- **Dismiss announcement.** On dismiss, VoiceOver announces `"Sheet dismissed, back on map"`.
- **Dynamic Type.** Tested at AX3. Title wraps to 2 lines before truncating. Metadata rows allow wrapping (never truncate coordinates — they must be copy-accurate).
- **Delete button hint.** See §4.
- **Coordinate row.** `accessibilityLabel = "Coordinate, <latitude> degrees <direction>, <longitude> degrees <direction>"`. `accessibilityCustomActions = [Copy]`. Avoid reading raw decimal — VoiceOver handles lat/long nicely with `"<value> degrees"`.
- **Stats row for route/polygon.** Each stat is a separate accessibility element with label (e.g. `"Distance"`) and value (e.g. `"430 meters"`).

## 8. Acceptance criteria

- [ ] Sheet uses `.medium` + `.large` detents with auto-promote on keyboard
- [ ] Read-mode shows map pannable underneath (`.largestUndimmedDetentIdentifier = .medium`)
- [ ] Edit-mode toolbar has Cancel + Save with the correct enable/disable logic
- [ ] Swipe-to-dismiss with unsaved changes fires the discard action sheet
- [ ] Destructive delete confirmation includes the annotation title
- [ ] All 4 annotation types render with correct icon + color per [00 §1](./00-design-system.md#1-color-roles)
- [ ] Default-title fallback strings implemented for all 4 types
- [ ] Route and polygon show computed stats (distance, area, perimeter, vertex count)
- [ ] Route vertex removal via context menu works and writes through op-log
- [ ] AX3 Dynamic Type: sheet scrolls rather than truncates; title wraps; action buttons don't clip
- [ ] Dark-mode appearance verified via Xcode preview variants
- [ ] VoiceOver: sheet traps focus (modal), title auto-focuses, Delete announces hint
- [ ] All mutations flow through `AnnotationEngine` → op-log (no direct SQLite writes)
- [ ] Unit tests: save with empty title fills default; discard-changes alert appears only when dirty

## 9. Open questions for CTO

- **Undo.** Spec leaves undo to v0.3. Confirm acceptable for v0.2.0 demo.
- **Share.** Share uses system `UIActivityViewController` with a GeoJSON feature payload derived from the annotation. Confirm this matches the Exporters API shape (likely straightforward — the GeoJSON exporter is already merged per CHA-123 plan).
- **Attribution row.** With sync toggled off by default in v0.2.0, the attribution row currently has nothing to display. Proposal: hide it entirely when `SyncEngine.isEnabled == false`. Confirm or request alternative (e.g., always show `"Local only"`).
