#!/bin/zsh
#
# Put a LearnHarness icon on the Desktop (and in Applications) that runs
# scripts/mac/launch.sh: pull the latest code, then start or restart the
# app. Run once from the clone:  zsh scripts/mac/install-launcher.sh
# Re-run it if you move the clone.

set -eu
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LAUNCH="$REPO/scripts/mac/launch.sh"
chmod +x "$LAUNCH"

build_app() {
	local app="$1"
	rm -rf "$app"
	osacompile -o "$app" -e "do shell script quoted form of \"$LAUNCH\" & \" > /dev/null 2>&1 &\""
	cp "$REPO/build/icon.icns" "$app/Contents/Resources/applet.icns"
	codesign --force --deep --sign - "$app" >/dev/null 2>&1 || true
	touch "$app"
	echo "made $app"
}

build_app "$HOME/Desktop/LearnHarness.app"
mkdir -p "$HOME/Applications"
build_app "$HOME/Applications/LearnHarness.app"
echo "Double-click LearnHarness on your Desktop to start it. Drag it to the Dock to keep it there."
