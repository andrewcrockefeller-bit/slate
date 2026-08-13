#!/bin/bash
#
# Double-clickable: set up an SSH key for GitHub.
#
# Why SSH instead of fighting token scopes: personal access tokens are refused
# by GitHub when a push would create or update a workflow file unless the token
# carries the `workflow` scope. SSH keys are not scoped that way at all — they
# push whatever your account can push. They also do not expire, so this is the
# last time authentication needs any attention.
#
# This script only creates a key and copies it to the clipboard. It changes
# nothing about the repo and pushes nothing.

set -u

KEY="$HOME/.ssh/id_ed25519"

echo "──────────────────────────────────────────────────────────"
echo " GitHub SSH setup"
echo "──────────────────────────────────────────────────────────"
echo

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [ -f "$KEY" ]; then
    echo "An SSH key already exists at $KEY — reusing it."
else
    echo "Creating a new SSH key..."
    # -N "" means no passphrase: this key only pushes to your own repo from
    # your own machine, and a passphrase would mean typing it on every push.
    ssh-keygen -t ed25519 -C "andrewcrock@icloud.com" -f "$KEY" -N "" -q
    echo "Created."
fi

echo
echo "Starting ssh-agent and loading the key..."
eval "$(ssh-agent -s)" >/dev/null 2>&1
ssh-add --apple-use-keychain "$KEY" 2>/dev/null || ssh-add "$KEY" 2>/dev/null

# Persist across reboots without needing this script again.
CONFIG="$HOME/.ssh/config"
if ! grep -q "AddKeysToAgent" "$CONFIG" 2>/dev/null; then
    {
        echo "Host github.com"
        echo "  AddKeysToAgent yes"
        echo "  UseKeychain yes"
        echo "  IdentityFile $KEY"
    } >> "$CONFIG"
    chmod 600 "$CONFIG"
fi

pbcopy < "$KEY.pub"

echo
echo "──────────────────────────────────────────────────────────"
echo " YOUR PUBLIC KEY IS NOW ON THE CLIPBOARD."
echo "──────────────────────────────────────────────────────────"
echo
cat "$KEY.pub"
echo
echo " Next, in a browser:"
echo
echo "   1. Go to  https://github.com/settings/ssh/new"
echo "   2. Title:  MacBook Pro     (anything you like)"
echo "   3. Key type: Authentication Key"
echo "   4. Click the Key box and press Cmd-V to paste"
echo "   5. Click 'Add SSH key'"
echo
echo " Then double-click  Tools/push-ssh.command  to finish."
echo
echo " Only the PUBLIC key is copied. The private key never leaves"
echo " this Mac — that is the whole point of the key pair."
echo "──────────────────────────────────────────────────────────"
