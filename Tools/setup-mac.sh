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
step "0/6  Preflight"

# The initial commit was made through a remote file bridge that can create and
# write files but cannot unlink them. Git relies on unlink for its lock files
# and temporary loose objects, so it left both behind. A stale .git/index.lock
# blocks every subsequent write operation with a message that reads like
# corruption and is not; the tmp_obj_* files are harmless orphans that waste
# space and clutter fsck output.
#
# This runs on your Mac, where deletion works. Harmless when there is nothing
# to clean.
if [ -d .git ]; then
    stale_locks=$(find .git -type f \( -name '*.lock' -o -name 'tmp_obj_*' \) 2>/dev/null | wc -l | tr -d ' ')
    if [ "${stale_locks:-0}" -gt 0 ]; then
        dim "Clearing $stale_locks stale git lock/temp files left by the file bridge..."
        find .git -type f \( -name '*.lock' -o -name 'tmp_obj_*' \) -delete 2>/dev/null
        green "OK"
    else
        dim "No stale git state."
    fi
else
    dim "Not a git repository yet."
fi

# ---------------------------------------------------------------------------
# Stale build-plan guard.
#
# SwiftPM caches a build plan for each package, including the source file list
# of its local path dependencies. Adding a NEW file to SlateCore does not always
# invalidate SlatePlatform's cached plan, so SlatePlatform rebuilds SlateCore
# from a file list that predates the new file and fails with "cannot find type
# X in scope" — for a type that is plainly there, in a package that just
# compiled cleanly on its own a step earlier.
#
# That contradiction is the tell: same source, two builds, two answers. Rather
# than clean unconditionally (which costs minutes on every run), clean only when
# a SlateCore source is newer than the cached plan that is supposed to describe
# it.
PLAN="$ROOT/Packages/SlatePlatform/.build/debug.yaml"
if [ -f "$PLAN" ]; then
    if [ -n "$(find "$ROOT/Packages/SlateCore/Sources" -name '*.swift' -newer "$PLAN" -print -quit 2>/dev/null)" ]; then
        dim "SlateCore has sources newer than SlatePlatform's cached build plan."
        dim "Clearing it so the new files are picked up..."
        rm -rf "$ROOT/Packages/SlatePlatform/.build"
        green "OK"
    fi
fi

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

# Resolution order, cheapest first:
#   1. a previously built local copy inside this repo
#   2. xcodegen already on PATH (Homebrew, Mint, manual install)
#   3. Homebrew, if it happens to be installed
#   4. build from source with the Swift toolchain Xcode already provides
#
# (4) exists so that this project never requires Homebrew. Homebrew is a large
# system-wide dependency that wants a sudo password, and pulling one in
# sideways to install a build-time generator is not a trade worth making
# silently. XcodeGen builds fine with the toolchain you already have.

XCODEGEN_SRC="$ROOT/Tools/.xcodegen-src"
XCODEGEN_LOCAL="$XCODEGEN_SRC/.build/release/xcodegen"
XCODEGEN_PIN="$ROOT/Tools/xcodegen-version.txt"
XCODEGEN=""

if [ -x "$XCODEGEN_LOCAL" ]; then
    XCODEGEN="$XCODEGEN_LOCAL"
    dim "Using locally built XcodeGen."
elif command -v xcodegen >/dev/null 2>&1; then
    XCODEGEN="$(command -v xcodegen)"
    dim "Using XcodeGen from PATH."
elif command -v brew >/dev/null 2>&1; then
    dim "Installing XcodeGen with Homebrew..."
    if brew install xcodegen; then
        XCODEGEN="$(command -v xcodegen)"
    else
        fail "brew install xcodegen failed."
    fi
else
    dim "XcodeGen not found and no Homebrew. Building it from source."
    dim "This takes a few minutes the first time and never again."
    echo

    if ! command -v git >/dev/null 2>&1; then
        fail "git not found, so XcodeGen cannot be fetched."
    fi

    if [ ! -d "$XCODEGEN_SRC/.git" ]; then
        rm -rf "$XCODEGEN_SRC"
        if ! git clone --quiet https://github.com/yonaskolb/XcodeGen.git "$XCODEGEN_SRC"; then
            fail "Could not clone XcodeGen. Check your network."
        fi
    fi

    # Pin to whatever commit worked the first time, so a later run cannot
    # silently pick up a different generator and change the project.
    if [ -s "$XCODEGEN_PIN" ]; then
        PINNED="$(tr -d '[:space:]' < "$XCODEGEN_PIN")"
        dim "Checking out pinned commit $PINNED"
        if ! git -C "$XCODEGEN_SRC" checkout --quiet "$PINNED" 2>/dev/null; then
            dim "Pinned commit not found locally, fetching..."
            git -C "$XCODEGEN_SRC" fetch --quiet origin || true
            git -C "$XCODEGEN_SRC" checkout --quiet "$PINNED" \
                || fail "Could not check out pinned XcodeGen commit $PINNED."
        fi
    fi

    if ! ( cd "$XCODEGEN_SRC" && swift build -c release --product xcodegen ); then
        fail "Building XcodeGen from source failed."
    fi

    if [ ! -x "$XCODEGEN_LOCAL" ]; then
        fail "XcodeGen built but the binary is not where expected:
       $XCODEGEN_LOCAL"
    fi

    # Record the commit actually used, so this is reproducible from here on.
    if [ ! -s "$XCODEGEN_PIN" ]; then
        git -C "$XCODEGEN_SRC" rev-parse HEAD > "$XCODEGEN_PIN"
        dim "Pinned XcodeGen at $(cat "$XCODEGEN_PIN")"
        dim "Recorded in Tools/xcodegen-version.txt — commit this."
    fi

    XCODEGEN="$XCODEGEN_LOCAL"
fi

"$XCODEGEN" --version
green "OK"

# ---------------------------------------------------------------------------
step "6/6  Generate the Xcode project"

if ! "$XCODEGEN" generate; then
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
echo "      A white canvas, Apple's floating tool picker, and undo/redo/clear"
echo "      top-right. Draw one stroke with the Pencil; bottom-left should read"
echo "      something like:"
echo
echo "          SLATE  M1  1 strokes · last: 47 pts, 0.82s, pressure, tilt"
echo
echo "  That line is read out of the domain model, not out of PencilKit, so it"
echo "  is the cheapest proof that capture worked end to end."
echo
echo "  Do NOT test in the Simulator: the canvas is .pencilOnly, so a mouse"
echo "  scrolls rather than draws and it will look broken while working."
echo
echo "  The milestone is decided by feel, not by that line. See M1-test-plan.txt."
echo
dim "Re-run this script any time. After adding a source file, re-run it (or"
dim "'$XCODEGEN generate') so the project picks the file up."
echo
