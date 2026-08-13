#!/bin/bash
#
# Double-clickable: switch the remote to SSH and push.
#
# Run Tools/ssh-setup.command first and add the key to GitHub.

cd "$(dirname "$0")/.." || exit 1

if [ -d .git ]; then
    find .git -type f \( -name '*.lock' -o -name 'tmp_obj_*' \) -delete 2>/dev/null
fi

echo "──────────────────────────────────────────────────────────"
echo " Repo:   $(pwd)"
echo " Branch: $(git branch --show-current)"
echo "──────────────────────────────────────────────────────────"
echo

echo "Testing the SSH connection to GitHub..."
# GitHub always exits 1 on this even when it works, because it refuses an
# interactive shell. The greeting text is what matters, not the status.
ssh -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 | head -3
echo

echo "Pointing the remote at SSH..."
git remote set-url origin git@github.com:andrewcrockefeller-bit/slate.git
echo "  origin → $(git remote get-url origin)"
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
    echo " its tests on a machine with no Apple frameworks on it — the"
    echo " first real proof that Layer 1 is portable."
else
    echo " Failed (exit $status)."
    echo
    echo " If the SSH test above said 'Permission denied (publickey)',"
    echo " the key is not on your GitHub account yet. Run"
    echo " Tools/ssh-setup.command and add it at:"
    echo "   https://github.com/settings/ssh/new"
    echo
    echo " If it said 'Hi andrewcrockefeller-bit!' then SSH is fine and"
    echo " the problem is something else — send me this output."
fi
echo "──────────────────────────────────────────────────────────"
