#!/usr/bin/env bash
#
# One-command M0 setup for macOS.
#
#     ./Tools/setup-mac.sh
#
# Checks the toolchain, verifies layer purity, builds and tests both packages,
# and generates the Xcode project from project.yml. Safe to re-run at any time;
# it changes nothing outside this repo except installing XcodeGen if it is
# missing.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

bold()  { printf '\033[1m%s\033[0m\n' "$1"; }
green() { printf '\033[32m%s\033[0m\n' "$1"; }
red()   { printf '\033[31m%s\033[0m\n' "$1"; }
dim()   { printf '\033[2m%s\033[0m\n' "$1"; }

step()  { echo; bold "── $1"; }
fail()  { echo; red "FAILED: $1"; echo; dim "Send me the output above rather than working around it."; exit 1; }

echo
bold "Slate — M0 setup"
dim "$ROOT"

# ---------------------------------------------------------------------------
step "1/6  Toolchain"

if ! command -v xcodebuild >/dev/null 2>&1; then
    fail "Xcode is not installed, or the command line tools are not pointed at it.
       Install Xcode 16 or later, then run:
           sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
fi

XCODE_PATH="$(xcode-select -p)"
if [[ "$XCODE_PATH" == *CommandLineTools* ]]; then
    fail "xcode-select points at the Command Line Tools, not Xcode.
       Run:  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
fi

xcodebuild -version | head -1
swift --version 2>&1 | head -1

SWIFT_MAJOR="$(swift --version 2>&1 | grep -oE 'Swift version [0-9]+' | grep -oE '[0-9]+' | head -1)"
if [ -n "${SWIFT_MAJOR:-}" ] && [ "$SWIFT_MAJOR" -lt 6 ]; then
    fail "Swift $SWIFT_MAJOR found, but the packages declare swift-tools-version 6.0.
       Install Xcode 16 or later."
fi
green "OK"

# ---------------------------------------------------------------------------
step "2/6  Layer purity  (Invariant 1)"

if ! ./Tools/check-layer-purity.sh; then
    fail "Layer 1 contains something that is not pure Swift over Foundation."
fi

# ---------------------------------------------------------------------------
step "3/6  Layer 1 — SlateCore"
dim "The part that must stay portable. This is the real test of M0."

if ! swift test --package-path Packages/SlateCore; then
    fail "SlateCore did not build or its tests did not pass."
fi
green "OK"

# ---------------------------------------------------------------------------
step "4/6  Layer 2 — SlatePlatform"

if ! swift test --package-path Packages/SlatePlatform; then
    fail "SlatePlatform did not build or its tests did not pass."
fi
green "OK"

# ---------------------------------------------------------------------------
step "5/6  XcodeGen"

if ! command -v xcodegen >/dev/null 2>&1; then
    dim "XcodeGen not found."
    if command -v brew >/dev/null 2>&1; then
        dim "Installing with Homebrew..."
        if ! brew install xcodegen; then
            fail "brew install xcodegen failed."
        fi
    else
        fail "XcodeGen is not installed and Homebrew was not found.
       Install Homebrew from https://brew.sh, then re-run this script.
       XcodeGen is a build-time generator only — nothing in the app links
       against it. See docs/decisions.md."
    fi
fi

xcodegen --version
green "OK"

# ---------------------------------------------------------------------------
step "6/6  Generate the Xcode project"

if ! xcodegen generate; then
    fail "xcodegen generate failed. The spec is project.yml."
fi
green "OK — Slate.xcodeproj generated"

# ---------------------------------------------------------------------------
echo
green "════════════════════════════════════════════════════════════════"
green " M0 build verified."
green "════════════════════════════════════════════════════════════════"
echo
bold "What is left, and it needs you rather than a script:"
echo
echo "  1.  open Slate.xcodeproj"
echo "  2.  Select the Slate target > Signing & Capabilities."
echo "      Set Team to your Apple ID. A free account is fine; it signs"
echo "      builds that run on your own device for seven days."
echo "  3.  Plug in the iPad, unlock it, pick it in the destination menu,"
echo "      and press Cmd-R."
echo "  4.  First run stops at a signing error until you trust the"
echo "      certificate on the iPad:"
echo "          Settings > General > VPN & Device Management > Trust"
echo "      Then Cmd-R again."
echo
bold "What you should see on the iPad:"
echo
echo "      a near-white canvas, and bottom-left in small monospaced text:"
echo
echo "          SLATE  M0  stall 4.0s  cooldown 20.0s  config ok"
echo
echo "  Those numbers are read out of SlateCore. If they render, Layer 1 is"
echo "  linked and reachable from Layer 3, which is the whole on-device"
echo "  acceptance criterion for this milestone. Drawing does nothing yet —"
echo "  correct for M0. Ink is M1."
echo
dim "Re-run this script any time. After adding a source file, run"
dim "'xcodegen generate' so the project picks it up."
echo
