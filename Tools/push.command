#!/bin/bash
#
# Double-clickable: push the repo to GitHub and report the result.
#
# Exists so the push can be launched without typing a command. If git asks for
# credentials, type them into this window — the password is the personal access
# token, and the input is invisible by design, so paste it and press Return
# even though nothing appears.

cd "$(dirname "$0")/.." || exit 1

# The remote file bridge can create files but not unlink them, so git may have
# left lock files behind that block every write operation. Clearing them here
# is harmless when there is nothing to clear.
if [ -d .git ]; then
    find .git -type f \( -name '*.lock' -o -name 'tmp_obj_*' \) -delete 2>/dev/null
fi

echo "──────────────────────────────────────────────────────────"
echo " Repo:   $(pwd)"
echo " Remote: $(git remote get-url origin 2>/dev/null || echo 'NONE')"
echo " Branch: $(git branch --show-current)"
echo "──────────────────────────────────────────────────────────"
echo

git push -u origin main
status=$?

echo
echo "──────────────────────────────────────────────────────────"
if [ "$status" -eq 0 ]; then
    echo " Pushed successfully."
    echo
    echo " Now open the Actions tab:"
    echo "   https://github.com/andrewcrockefeller-bit/slate/actions"
    echo
    echo " Look for 'Layer 1 on Linux'. Green means SlateCore compiles"
    echo " and passes its tests on a machine with no Apple frameworks"
    echo " on it — the first real proof that Layer 1 is portable."
else
    echo " Push failed with exit status $status."
    echo
    echo " If it asked for a password: that field wants a personal access"
    echo " token, not your GitHub password. github.com/settings/tokens"
    echo " → Generate new token (classic) → tick 'repo'."
fi
echo "──────────────────────────────────────────────────────────"
