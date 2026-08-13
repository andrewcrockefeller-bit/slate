#!/usr/bin/env bash
#
# Invariant 1, enforced mechanically.
#
# Layer 1 (SlateCore) is pure Swift over Foundation. It has no dependencies and
# imports no other framework. This script fails the build if that stops being
# true, because "we'll notice in review" does not survive a year of milestones,
# and the first Apple type to sneak into the domain core is the one that makes
# the Android port a rewrite instead of a port.
#
# Runs in CI on every push and is worth running locally before you commit.
#
# Note: line comments are stripped before scanning, so prose that mentions
# PencilKit or CGFloat in a doc comment does not trip the check.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="$ROOT/Packages/SlateCore"
CORE_SOURCES="$CORE/Sources"
CORE_TESTS="$CORE/Tests"

# Imports permitted in the domain core itself. This list should never grow.
ALLOWED_SOURCE_IMPORTS='Foundation'

# Tests additionally need the test framework and the module under test.
ALLOWED_TEST_IMPORTS='Foundation|XCTest|SlateCore'

# Types that exist on Apple platforms without an explicit import, because
# Foundation re-exports CoreFoundation there. These are the ones that compile
# happily on a Mac and break the Linux build — the whole reason this check
# cannot just look at import lines.
FORBIDDEN_TOKENS='\bCG[A-Z][A-Za-z0-9_]*|\bUI[A-Z][A-Za-z0-9_]*|\bNS[A-Z][A-Za-z0-9_]*|\bPK[A-Z][A-Za-z0-9_]*|\bCK[A-Z][A-Za-z0-9_]*'

failures=0

red()   { printf '\033[31m%s\033[0m\n' "$1"; }
green() { printf '\033[32m%s\033[0m\n' "$1"; }
dim()   { printf '\033[2m%s\033[0m\n' "$1"; }

strip_comments() {
    sed 's://.*::'
}

report() {
    red "  FAIL  $1"
    failures=$((failures + 1))
}

# ---------------------------------------------------------------------------
dim "Checking Layer 1 imports..."

check_imports() {
    local dir="$1"
    local allowed="$2"
    local label="$3"

    [ -d "$dir" ] || return 0

    while IFS= read -r -d '' file; do
        while IFS= read -r module; do
            if [[ ! "$module" =~ ^($allowed)$ ]]; then
                report "$label: ${file#"$ROOT/"} imports '$module'"
            fi
        done < <(
            strip_comments < "$file" \
            | grep -oE '^[[:space:]]*(@testable[[:space:]]+)?import[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' \
            | awk '{print $NF}' \
            | sort -u
        )
    done < <(find "$dir" -name '*.swift' -print0)
}

check_imports "$CORE_SOURCES" "$ALLOWED_SOURCE_IMPORTS" "import"
check_imports "$CORE_TESTS"   "$ALLOWED_TEST_IMPORTS"   "import"

# ---------------------------------------------------------------------------
dim "Checking Layer 1 for Apple-only types..."

while IFS= read -r -d '' file; do
    matches="$(strip_comments < "$file" | grep -onE "$FORBIDDEN_TOKENS" || true)"
    if [ -n "$matches" ]; then
        while IFS= read -r hit; do
            report "type: ${file#"$ROOT/"}:${hit%%:*} uses '${hit#*:}'"
        done <<< "$matches"
    fi
done < <(find "$CORE_SOURCES" "$CORE_TESTS" -name '*.swift' -print0 2>/dev/null)

# ---------------------------------------------------------------------------
dim "Checking Layer 1 has no package dependencies..."

if grep -qE '^[[:space:]]*\.package\(' "$CORE/Package.swift"; then
    report "manifest: SlateCore declares a package dependency"
fi

# ---------------------------------------------------------------------------
dim "Checking Layer 1 does not depend on Layer 2..."

if grep -rqE '\bSlatePlatform\b' "$CORE_SOURCES" 2>/dev/null; then
    report "layering: SlateCore references SlatePlatform"
fi

# ---------------------------------------------------------------------------
echo
if [ "$failures" -eq 0 ]; then
    green "Layer purity OK — SlateCore is Foundation-only."
    exit 0
else
    red "Layer purity FAILED with $failures violation(s)."
    echo
    dim "Layer 1 is pure Swift over Foundation. If you need a platform"
    dim "capability, declare a protocol in SlateCore and implement it in"
    dim "SlatePlatform. Do not relax this check."
    exit 1
fi
