#!/bin/bash
#
# Double-clickable: forget the cached GitHub credential, then push.
#
# Why this exists separately from push.command: macOS Keychain caches the first
# token that successfully authenticates, and git keeps sending that one forever.
# So if you generate a NEW token with wider scopes, git never uses it — it keeps
# presenting the old, under-scoped one and the push keeps failing for a reason
# the error message does not mention.
#
# This clears the stored credential so git has to ask again. You will be
# prompted for a username and password:
#
#   Username: andrewcrockefeller-bit
#   Password: paste your personal access token (NOT your GitHub password)
#
# The password field shows nothing at all as you paste — no dots, no cursor
# movement. That is deliberate. Paste with Cmd-V and press Return.
#
# The token must have BOTH scopes ticked:  repo   workflow

cd "$(dirname "$0")/.." || exit 1

if [ -d .git ]; then
    find .git -type f \( -name '*.lock' -o -name 'tmp_obj_*' \) -delete 2>/dev/null
fi

echo "──────────────────────────────────────────────────────────"
echo " Repo:   $(pwd)"
echo " Remote: $(git remote get-url origin 2>/dev/null || echo 'NONE')"
echo " Branch: $(git branch --show-current)"
echo "──────────────────────────────────────────────────────────"
echo

echo "Clearing the cached GitHub credential..."
printf "protocol=https\nhost=github.com\n\n" | git credential-osxkeychain erase 2>/dev/null
echo "Cleared. Git will ask for credentials below."
echo
echo "  Username: andrewcrockefeller-bit"
echo "  Password: paste your token — the screen stays blank, that's normal"
echo

git push -u origin main
status=$?

echo
echo "──────────────────────────────────────────────────────────"
if [ "$status" -eq 0 ]; then
    echo " Pushed."
    echo
    echo " Open the Actions tab:"
    echo "   https://github.com/andrewcrockefeller-bit/slate/actions"
    echo
    echo " 'Layer 1 on Linux' green means SlateCore compiles and passes"
    echo " its tests on a machine with no Apple frameworks on it."
else
    echo " Still failing (exit $status)."
    echo
    echo " If the error mentions 'workflow' scope, the token being used"
    echo " does not have it. Check at github.com/settings/tokens that the"
    echo " token lists BOTH 'repo' and 'workflow' under its name."
fi
echo "──────────────────────────────────────────────────────────"
