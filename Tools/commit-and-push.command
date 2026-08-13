#!/bin/bash
#
# Double-clickable: stage, commit, and push over SSH.
#
# Exists so the whole verify-and-push loop can run without typing a command.
# The commit message is passed as the first argument, or falls back to a dated
# default. Safe to run with nothing staged — it says so and pushes anyway, in
# case a previous commit never made it to the remote.

cd "$(dirname "$0")/.." || exit 1

MESSAGE="${1:-Checkpoint $(date '+%Y-%m-%d %H:%M')}"

# The remote file bridge can create files but not unlink them, so git may have
# left lock files behind that block every write operation.
find .git -type f \( -name '*.lock' -o -name 'tmp_obj_*' \) -delete 2>/dev/null

echo "──────────────────────────────────────────────────────────"
echo " Repo:   $(pwd)"
echo " Branch: $(git branch --show-current)"
echo " Remote: $(git remote get-url origin 2>/dev/null || echo NONE)"
echo "──────────────────────────────────────────────────────────"
echo

if [ -n "$(git status --porcelain)" ]; then
    echo "Staging and committing..."
    git add -A
    git commit -m "$MESSAGE" || echo "  (commit reported nothing to do)"
else
    echo "Working tree already clean — nothing new to commit."
fi

echo
echo "Pushing..."
git push -u origin "$(git branch --show-current)"
status=$?

echo
echo "──────────────────────────────────────────────────────────"
if [ "$status" -eq 0 ]; then
    echo " Pushed. CI is now running."
    echo
    echo "   https://github.com/andrewcrockefeller-bit/slate/actions"
    echo
    echo " 'Layer 1 on Linux' green means SlateCore compiles and passes"
    echo " its tests on a machine with no Apple frameworks on it."
else
    echo " Push failed with exit status $status."
    echo
    echo " If it mentions publickey, run Tools/ssh-setup.command and add"
    echo " the key at https://github.com/settings/ssh/new"
fi
echo "──────────────────────────────────────────────────────────"
