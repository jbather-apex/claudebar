#!/bin/bash
# Build ClaudeBar locally and install it to /Applications.
# Local builds carry no quarantine attribute, so Gatekeeper stays quiet.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/make-app.sh

if pgrep -x ClaudeBar >/dev/null; then
    pkill -x ClaudeBar
    sleep 1
fi

rm -rf /Applications/ClaudeBar.app
cp -R dist/ClaudeBar.app /Applications/ClaudeBar.app

open /Applications/ClaudeBar.app
echo "Installed /Applications/ClaudeBar.app"
