# 05 — Cluster Badge

**Scope:** The visual that replaces multiple nearby annotations at low zoom levels, with tap-to-expand behavior. Typography, contrast, size variants by count, behavior at the zoom-12 threshold.

**Related:** [00 Design System](./00-design-system.md), [PRD CG-006](../../../docs/PRD.md) (clustering activates at zoom < 12).

## 1. Clustering rule (from PRD)

- **Activate below zoom 12.** At zoom level ≥ 12, every annotation renders individually.
- **Cluster grouping**: annotations within a geometric radius on screen (not map distance) are grouped into a single cluster badge positioned at the weighted centroid of constituent annotations.
- **R-tree query** returns annotations in the viewport; clustering happens **after** query, on the UI thread, via a simple grid-based cluster (e.g., 44pt cells on screen — this is MapCoordinator's concern).

This spec governs the **visual + interaction** of the resulting badge.

## 2. Visual anatomy

A cluster badge is a filled circle with a numeric label centered inside.

```
       ╱───────╲
      │    7    │   ← count
       ╲───────╱
```

### 2.1 Sizing by count (three variants)

| Count range | Diameter | Border (outer ring) |
|---|---|---|
| 2–9 | 32pt | 2pt `cluster.badge.fill` @ 60% alpha |
| 10–99 | 40pt | 2.5pt `cluster.badge.fill` @ 60% alpha |
| 100+ | 48pt | 3pt `cluster.badge.fill` @ 60% alpha |

**Why 3 sizes (not continuous or 2).** 32 / 40 / 48 are perceptually distinct at glance without introducing too many variants. Continuous sizing creates pixel jitter on zoom changes. Two sizes are too coarse for a product meant to scale to 10K annotations.

**Outer ring.** The 60% alpha ring provides halo contrast against noisy tile backgrounds (trees, water edges). It does NOT scale with cluster count — ring thickness scales with diameter per table above.

**Inner fill.** `cluster.badge.fill` = systemBlue. Opaque (100% alpha).

### 2.2 Typography

| Property | Value |
|---|---|
| Font token | `type.cluster` (from [00 §2](./00-design-system.md#2-typography)) |
| Apple style | `.headline` |
| Weight | `.semibold` |
| **Monospaced digits** | **Yes** — `UIFont.monospacedDigitSystemFont(ofSize:, weight:)` or SwiftUI `.monospacedDigit()` |
| Color | `cluster.badge.label` (white) |
| Size (literal pt) | 15pt for 32pt badge, 17pt for 40pt badge, 20pt for 48pt badge |

**Why monospaced digits.** When users zoom and a cluster count transitions `9 → 10`, the glyph width must not change. Without monospaced digits, `1` takes less width than `0`, and the count appears to jitter. This is the #1 polish issue in stock MapKit clustering.

**Why `.headline` not Dynamic-Type-scaling.** Cluster badges are map overlays, not primary content. They must stay pixel-stable so map layout doesn't reflow when the user changes system text size. Accessibility is carried via VoiceOver label (see §5), not visual scaling.

### 2.3 Large count formatting

| Count | Rendered label |
|---|---|
| 2–99 | Literal number: `2`, `47`, `99` |
| 100–999 | Literal number: `234`, `999` |
| 1000–9999 | `1.2k`, `9.9k` (one decimal, lowercase `k`) |
| ≥ 10000 | `10k+`, `50k+`, `99k+` (no decimal; plus suffix) |

Trade-off noted. Showing literal 10000 would require a larger badge. The `k`-suffix keeps the badge at 48pt and preserves the three-size hierarchy. When the user taps a 10k+ cluster, they see the exact count in the expansion affordance (see §4).

## 3. Color contrast (WCAG AA on OSM tiles)

The badge must pass **3:1 contrast** (WCAG AA for UI components) against OpenStreetMap tiles in both light and dark map styles. Text inside the badge must pass **4.5:1 contrast** (body text minimum).

### 3.1 Light map style

- `systemBlue` fill (#007AFF sRGB) on top of typical OSM light tiles (whites, pale greens, sandy yellows, ocean blues).
- White text on `systemBlue`: contrast ≈ 4.8:1 ✅
- `systemBlue` on white map background: contrast ≈ 4.5:1 ✅ (meets AA)
- `systemBlue` on OSM ocean blue (#A8CCE0): contrast ≈ 2.1:1 ❌ — fails without halo

**Halo mitigation (required).** A 2pt stroke in `systemBackground` around the entire badge (outside the outer ring) guarantees 3:1 against any tile by sandwiching the badge in a white/black ring regardless of tile color.

Stack order (outer to inner):
1. 2pt halo stroke, `systemBackground` — this layer is the contrast guarantee
2. Outer ring: 2–3pt `cluster.badge.fill` @ 60% alpha
3. Inner fill: `cluster.badge.fill` @ 100%
4. Count label: white, `type.cluster`

Total visual width = diameter + 2×(outer ring thickness) + 2×(halo stroke thickness). For 32pt variant: 32 + 4 + 4 = **40pt total footprint** on screen. The R-tree hit-test target is the full footprint.

### 3.2 Dark map style

- Background: `systemBackground` in dark mode = near-black (#1C1C1E or so).
- `systemBlue` on dark background: contrast ≈ 4.6:1 ✅
- White text on `systemBlue`: contrast ≈ 4.8:1 ✅ (unchanged; blue is dark-enough)
- Halo stroke in dark mode becomes near-black (`systemBackground`), which sandwiches the blue badge against brighter tile areas (pale yellows, whites that appear in dark OSM — e.g., some road overlays).

### 3.3 Increase Contrast accessibility

When `UIAccessibility.isDarkerSystemColorsEnabled == true`:
- Inner fill switches to `UIColor.systemBlue.accessibleVariant` (Apple's increased-contrast variant, darker in light mode, lighter in dark mode).
- Outer ring alpha increases from 60% to 80%.
- Halo stroke width increases from 2pt to 3pt.
- Text weight increases from `.semibold` to `.bold`.

### 3.4 Verification checklist for iOS Engineer

Test against these OSM tile samples (light + dark each):
- Urban: NYC Midtown (mostly grey roads, white buildings)
- Rural: Scottish Highlands (mostly greens and browns)
- Coastal: Florida Keys (ocean blue dominant) — the hardest case
- Dense: Tokyo (high road density, coral/yellow labels)

Capture a screenshot per style per tile sample with a cluster badge overlaid and run through Xcode's Accessibility Inspector contrast check. All must pass 3:1 for UI, 4.5:1 for the text inside.

## 4. Interaction

### 4.1 Tap on cluster

**Behavior.** Tapping a cluster zooms in to fit the cluster's bounding box with a `.easeInOut` animation over 280ms. If zooming to fit takes the map beyond zoom 12, clustering breaks apart automatically per §4.3.

**Haptic.** None on tap. The visual zoom + break-apart is sufficient feedback.

### 4.2 Long-press on cluster

Out of scope for v0.2.0. (Future: could show a mini-list of annotations within the cluster.) Long-press on a cluster is a no-op in v0.2.0.

### 4.3 Break-apart at the zoom-12 threshold

**Crossing zoom 12 upward (zooming in).**
- When the map's zoom crosses from `< 12` to `≥ 12` (either by pinch, double-tap, or cluster-tap-zoom), each visible cluster "breaks apart":
  - Cluster badge fades from 100% → 0% opacity over 180ms, concurrent with…
  - Constituent annotation views appear, positioned initially at the cluster centroid, then animate radially outward to their true positions over 220ms with `.easeOut`.
- **Reduce Motion variant.** No radial motion. Cluster badge opacity-fades to 0 over 180ms; constituent annotations appear in place (opacity 0 → 100%) over 180ms, staggered by 0ms each (simultaneous).

**Crossing zoom 12 downward (zooming out).**
- Reverse: constituent annotations collapse to centroid over 220ms, cluster badge fades in.
- **Reduce Motion variant.** Constituent annotations opacity-fade to 0; cluster badge opacity-fades in. No translation.

**Edge case: the threshold straddled by rapid zoom.** If the user pinches fast enough to cross zoom 12 twice within 300ms, we cancel in-flight animations and snap to the final state (clustered or expanded based on final zoom). No half-state.

**No haptic.** Crossing the zoom threshold is a passive gesture consequence, not an intentional action. Per [00 §5](./00-design-system.md#5-motion--haptics) haptic policy: no haptic.

### 4.4 Selection state

A cluster cannot be "selected" — it's ephemeral. Tapping expands it. If the user wants to see details for annotations inside the cluster, they must zoom in enough to break the cluster apart, then tap an individual annotation.

## 5. Accessibility

### 5.1 VoiceOver label

`accessibilityLabel = "Cluster of <N> annotations."` where `<N>` is the literal count (not k-formatted).

`accessibilityHint = "Double-tap to zoom in and see individual annotations."`

`accessibilityValue` — omit. The count is in the label.

### 5.2 VoiceOver traits

Cluster badge is a **button** trait (`UIAccessibilityTraits.button`).

### 5.3 Custom rotor

The map's `accessibilityCustomRotors` include a rotor named `"Clusters"` that cycles visible clusters in distance-from-viewport-center order. Exposes to VoiceOver users the ability to jump between dense areas without having to swipe through individual annotations.

### 5.4 Very-large-text users

Because the badge does not scale with Dynamic Type (see §2.2 rationale), users at AX2+ instead rely on:
- VoiceOver label (always includes exact count)
- Rotor navigation
- The annotation list view accessible from the Debug menu (v0.2.0) or Project view (v0.3)

## 6. Performance constraints

- **60fps during pan at 5K annotations.** The PRD target is `< 16ms` frame time. Clustering math must run off the main thread OR be so cheap it completes during `regionDidChangeAnimated`. Recommended implementation: bucket annotations into a 44pt screen grid using integer coordinate math on a background queue, then commit to MapKit on main.
- **No CALayer shadow for the halo.** Use a second `CAShapeLayer` (stroke only) instead of `shadowPath` — `CALayer.shadowPath` triggers offscreen rendering which tanks pan frame rate with 100+ clusters.
- **Batched updates.** When zoom changes by > 0.5 levels, do not update cluster visuals mid-flight; commit the final state when zoom stabilizes. Use `regionDidChangeAnimated` debounced 100ms.

## 7. Acceptance criteria

- [ ] Three size variants (32 / 40 / 48pt) for count ranges 2–9, 10–99, 100+
- [ ] Monospaced digits verified (visually: `9 → 10` does not shift other elements horizontally)
- [ ] Large-count formatting: 1.2k, 9.9k, 10k+, 50k+, 99k+
- [ ] Halo stroke (`systemBackground`) present and visible against OSM water tiles
- [ ] Contrast: 3:1 against all 4 tile test samples (§3.4), both light and dark, AA
- [ ] Text contrast (white on blue): 4.5:1 — passes
- [ ] `Increase Contrast` variant increases outer ring alpha, halo thickness, font weight
- [ ] Tap zooms in to fit cluster bounding box (280ms ease-in-out)
- [ ] Crossing zoom 12 upward: cluster fade-out + radial pin appear (220ms)
- [ ] Crossing zoom 12 downward: pins collapse + cluster fade-in
- [ ] Reduce Motion: opacity-only transitions at both thresholds
- [ ] Rapid-zoom edge case: final state snaps correctly, no half-state
- [ ] VoiceOver: label has exact count, button trait, hint tells user about zoom-in
- [ ] Custom rotor `"Clusters"` cycles visible clusters
- [ ] Pan with 5K synthetic annotations: < 16ms frame time measured by Instruments
- [ ] No `CALayer.shadowPath` used; halo via `CAShapeLayer`

## 8. Open questions for CTO

- **Cluster grid size.** Spec assumes 44pt screen grid for clustering. This balances perceptual grouping with minimum tap target. Confirm or ask for a different constant.
- **Type mixing within a cluster.** If a cluster contains both pins and polygons, the badge currently shows only a count. Question: should we colorize the ring based on the dominant annotation type? v0.2.0 recommendation is **no** — keeps the badge simple and the semantic unambiguous ("this is a count of stuff here"). v0.3 could explore mini-pie segmentation.
- **k-formatting breakpoint.** Spec uses `1000` as the threshold. For users with small fields of view, `999 → 1.0k` is sudden; `1000 → 1.0k` is less so because `1000` barely fits the 48pt badge. Confirm the cutover at 1000.
