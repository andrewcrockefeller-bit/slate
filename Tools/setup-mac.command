#!/bin/bash
#
# Double-clickable wrapper around Tools/setup-mac.sh.
#
# Exists because macOS runs a .command file in Terminal when you double-click
# it, which means the whole setup can be triggered from Finder without anyone
# typing a command. Useful when driving the machine remotely, and harmless
# otherwise — it does nothing the script does not already do.

cd "$(dirname "$0")/.." || exit 1
./Tools/setup-mac.sh

echo
echo "──────────────────────────────────────────────────────────"
echo " Finished. Exit status: $?"
echo " You can close this window."
echo "──────────────────────────────────────────────────────────"
