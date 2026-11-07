#!/bin/zsh
#
# Install LearnHarness.app in ~/Applications: click it (or keep it in the
# Dock) to pull the latest code and start or restart the app. Run once from
# the clone, in Terminal:  zsh scripts/mac/install-launcher.sh
# Re-run it after moving the clone, or when the launcher says Electron was
# updated.

set -eu
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
chmod +x "$REPO/scripts/mac/launch.sh"
[[ -d "$REPO/node_modules" ]] || (cd "$REPO" && npm install)

mkdir -p "$HOME/Applications"
zsh "$REPO/scripts/mac/brand-electron.sh" "$REPO" "$HOME/Applications/LearnHarness.app"

# The first launcher was a script applet on the Desktop; it still works,
# but one app is enough.
if [[ -d "$HOME/Desktop/LearnHarness.app" && -f "$HOME/Desktop/LearnHarness.app/Contents/Resources/Scripts/main.scpt" ]]; then
	rm -rf "$HOME/Desktop/LearnHarness.app" && echo "removed the old Desktop launcher"
fi

killall Dock 2>/dev/null || true # redraw cached icons
open -R "$HOME/Applications/LearnHarness.app"
echo "Done. Drag LearnHarness from the Finder window that just opened into your Dock, and click it to start."
