#!/usr/bin/env bash
# Regenerate the app screenshots embedded in README.md.
#
# What this does:
#   1. Picks (or boots) an iOS 18.x iPhone simulator.
#   2. Builds the CartographerDemo iOS app with xcodebuild.
#   3. Installs the produced .app on the simulator and launches it by bundle id.
#   4. Captures a PNG with `xcrun simctl io <device> screenshot`, then resizes
#      to ~1080px wide via `sips`. Writes to docs/images/.
#
# Requirements:
#   - Xcode 16+ with an iOS 18.x simulator runtime.
#   - A booted iOS 18.x simulator OR CAPTURE_DEVICE_ID set to an explicit UDID.
#
# The captured filenames are referenced from README.md — keep them stable when
# editing this script. Adding a new shot means: (a) extend `capture` calls
# below, (b) reference the new file in README.md.
#
# Pattern mirrors vivekptnk/Iris's capture-screenshots.sh. Convergence is
# intentional — see CHA-174 / CHA-196.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_ROOT/CartographerDemo/CartographerDemo.xcodeproj"
SCHEME="CartographerDemo"
BUNDLE_ID="com.garnathdynamics.cartographer.demo"
OUT_DIR="$REPO_ROOT/docs/images"
DD="${DERIVED_DATA:-/tmp/cartographer-demo-dd}"

pick_device() {
  if [[ -n "${CAPTURE_DEVICE_ID:-}" ]]; then
    echo "$CAPTURE_DEVICE_ID"
    return
  fi
  local booted
  booted=$(xcrun simctl list devices booted | awk -F '[()]' '/iPhone/ {print $2; exit}')
  if [[ -n "$booted" ]]; then
    echo "$booted"
    return
  fi
  echo "No booted simulator; booting iPhone 16 (iOS 18.x)." >&2
  local udid
  udid=$(xcrun simctl list devices available \
    | awk '/-- iOS 18/{flag=1;next} /^--/{flag=0} flag && /iPhone 16 \(/' \
    | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/' | head -n1)
  if [[ -z "$udid" ]]; then
    echo "Could not find an iOS 18 iPhone 16 simulator. Install one via Xcode." >&2
    exit 1
  fi
  xcrun simctl boot "$udid" || true
  echo "$udid"
}

build_and_install() {
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$DEVICE" \
    -derivedDataPath "$DD" \
    build >/tmp/cartographer-build.log 2>&1 || {
      tail -120 /tmp/cartographer-build.log
      exit 1
    }

  local app
  app=$(find "$DD/Build/Products/Debug-iphonesimulator" -maxdepth 2 -name "${SCHEME}.app" -print -quit)
  if [[ -z "$app" ]]; then
    echo "Could not locate built .app under $DD/Build/Products/Debug-iphonesimulator" >&2
    exit 1
  fi
  xcrun simctl install "$DEVICE" "$app" >/dev/null
  echo "Installed $app on $DEVICE"
}

capture() {
  local name="$1" appearance="$2" wait_seconds="$3" ; shift 3
  xcrun simctl ui "$DEVICE" appearance "$appearance" >/dev/null 2>&1 || true
  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
  sleep 1
  xcrun simctl launch "$DEVICE" "$BUNDLE_ID" "$@" >/dev/null
  sleep "$wait_seconds"
  local raw="/tmp/cartographer-shot-$name.png"
  xcrun simctl io "$DEVICE" screenshot "$raw" >/dev/null
  sips -Z 1080 "$raw" --out "$OUT_DIR/$name.png" >/dev/null
  echo "Wrote $OUT_DIR/$name.png"
}

DEVICE="$(pick_device)"
mkdir -p "$OUT_DIR"
build_and_install

# Default state: initial map view, light appearance.
# MapKit tile fetches need a moment to settle; 6s is conservative.
capture screenshot-map-view light 6

echo "Wrote screenshots to $OUT_DIR"
