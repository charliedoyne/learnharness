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
	# Newer macOS draws an applet's icon from Assets.car (CFBundleIconName),
	# not applet.icns: drop both so the LearnHarness icon file wins.
	cp "$REPO/build/icon.icns" "$app/Contents/Resources/applet.icns"
	rm -f "$app/Contents/Resources/Assets.car"
	/usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$app/Contents/Info.plist" 2>/dev/null || true
	/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile applet" "$app/Contents/Info.plist" 2>/dev/null \
		|| /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string applet" "$app/Contents/Info.plist"
	codesign --force --deep --sign - "$app" >/dev/null 2>&1 || true
	touch "$app"
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app" >/dev/null 2>&1 || true
	echo "made $app"
}

build_app "$HOME/Desktop/LearnHarness.app"
mkdir -p "$HOME/Applications"
build_app "$HOME/Applications/LearnHarness.app"
killall Dock 2>/dev/null || true # redraw cached icons
echo "Double-click LearnHarness on your Desktop to start it. Drag it to the Dock to keep it there."
