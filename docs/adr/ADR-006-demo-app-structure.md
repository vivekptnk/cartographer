# ADR-006: Demo App Target Structure — Companion Xcode Project

## Status
Accepted

## Context
Cartographer ships as a pure Swift Package (`Package.swift` at repo root, products: `Cartographer` library). CHA-137 adds a `CartographerDemo` iOS app that exercises the full engine on a real device.

SwiftPM cannot produce an iOS `.app` bundle on its own. `executableTarget` builds a bare Mach-O with no `Info.plist`, no launch storyboard, no asset catalog, no code-signing entitlements, no bundle ID — none of the machinery `xcodebuild`/`CoreSimulator`/`AMDevice` require to install on an iPhone. The Xcode "Swift package executables run on iOS" path (SE-0294-era tooling) is still read-only from the SwiftPM side; it relies on Xcode-generated project scaffolding at use time.

We looked at three options:

| Option | What it is | Pros | Cons |
|---|---|---|---|
| **A. Companion `.xcodeproj` checked in** | Hand-maintained `CartographerDemo.xcodeproj` at repo root referencing the local SPM package as a local-package dependency | `xcodebuild -scheme CartographerDemo …` works out of the box. No extra tools. Matches what Xcode's "File → New → Project" produces. | `.pbxproj` is a pseudo-INI blob that is tedious to review and merge-conflict-prone. |
| **B. Nested SwiftPM `executableTarget` + Xcode host shell** | SPM target holds the Swift sources; a thin Xcode project provides Info.plist/assets/signing and links the target | Sources live inside SPM, so `swift build` sees them | Still requires a checked-in `.xcodeproj`. Adds a layer (SPM ↔ Xcode target) without removing either. Strict-concurrency flags diverge between SPM and Xcode build settings. |
| **C. XcodeGen-only (`project.yml`)** | A declarative text spec; `xcodegen generate` produces the project on demand | `project.yml` is easy to review and merge | Requires `brew install xcodegen` before `xcodebuild` works. CI must install it. Breaks the "clone and build" flow. |

## Decision

**Adopt Option A with a single twist:** we also check in an `XcodeGen`-compatible `project.yml` **alongside** the hand-maintained `.xcodeproj`. The `.xcodeproj` is the source of truth that `xcodebuild` reads; the `project.yml` is a diffable mirror that makes structural review of the project file practical (you diff the YAML in PRs, then regenerate or hand-patch the `.pbxproj`). XcodeGen is not required to build the demo — it is a reviewer and maintainer convenience.

Layout:

```
<repo-root>/
├── Package.swift                              # unchanged; engine library only
├── Sources/Cartographer/…                     # engine library, platform-neutral
├── CartographerDemo/
│   ├── CartographerDemo.xcodeproj/            # checked in, authoritative
│   │   └── project.pbxproj
│   ├── project.yml                            # XcodeGen mirror; advisory, not required
│   ├── CartographerDemo/                      # iOS app sources (SwiftUI)
│   │   ├── CartographerDemoApp.swift          # @main
│   │   ├── AppContainer.swift                 # engine wiring root
│   │   ├── Views/…                            # map shell, debug menu, annotation sheet
│   │   ├── Services/…                         # demo-only services (share sheet, etc.)
│   │   ├── Resources/
│   │   │   └── Assets.xcassets                # app icon, accent color (placeholder)
│   │   └── Info.plist                         # iOS 17+, UIApplicationSceneManifest
│   └── README.md                              # how to open, how to build, how to run
```

Rules:
- The `.xcodeproj` references the repo root's `Package.swift` as a **local package dependency** (`XCLocalSwiftPackageReference`), so the engine is always built from source against the current tree.
- `CartographerDemo/` **never** imports private engine internals. It consumes the public `Cartographer` product only.
- No runtime third-party dependencies: Apple frameworks (MapKit, SwiftUI, CoreLocation, CloudKit, UIKit, CoreGraphics) and the `Cartographer` SPM product only. This preserves the project-wide zero-dep rule.
- `project.yml` is kept in sync on every structural change (new file group, new target, new build setting). CI does not run `xcodegen` — it just runs `xcodebuild`.
- The demo target's iOS deployment target matches the engine's: **iOS 17**.

## Rationale
- **Exit criteria demand `xcodebuild` and real-device install.** That forces a real Xcode project. Option C adds a tool dependency for every clone; Option A does not.
- **`Package.swift` stays clean.** The engine is reusable as a library from any consumer. Folding the demo app into `Package.swift` would force SwiftUI/UIKit imports into the package graph, which breaks macOS library consumers and violates CLAUDE.md's "pure Swift, no UI dependencies in the engine layer".
- **PR review cost stays bounded.** The pain point with hand-maintained `.pbxproj` is review. Shipping the `project.yml` mirror lets reviewers read a 60-line YAML instead of a 600-line PEG. The `.xcodeproj` itself only changes when structure changes — day-to-day file adds go through Xcode's "Add files to target" and the diff is localized.
- **Local-package reference keeps the engine honest.** There is no "published" engine version to pin. Every build of the demo is a build of `main`. If an engine PR breaks the public API the demo build breaks immediately.

## Consequences
- Two files to keep in sync when adding targets or changing build settings: the `.pbxproj` and `project.yml`. Day-to-day file additions only touch the `.pbxproj`.
- Contributors who prefer declarative project definitions may run `xcodegen generate` locally after editing `project.yml` to regenerate the `.pbxproj`; the regenerated file should round-trip cleanly in git.
- The demo target is iOS-only for v0.2.0. A macOS demo would get its own target in the same project file behind a later ADR.
- Apple may add first-class SwiftPM iOS-app support in a future Xcode. If that happens, we revisit this ADR — migration would be a single folder move plus dropping the `.xcodeproj` entries.

## Alternatives revisited
We explicitly rejected:
- **Tuist / Bazel / Buck** — third-party build systems violate the zero-dep rule for the entire build graph, not just runtime.
- **Shipping the `.xcodeproj` as the sole source with no YAML mirror** — the review burden is real and worth the extra file.
- **Generating the project at test time in CI only** — creates a "works on my machine" gap between local dev (has project) and CI (generates project); any drift between the two is invisible until a PR fails.

## References
- CHA-137 — this ticket
- CHA-123 plan — overall v0.2.0 roadmap
- CLAUDE.md — zero-dependency rule, engine/app layer separation
