#!/bin/zsh
#
# Build LearnHarness.app: a renamed copy of this clone's Electron.app with
# the LearnHarness icon, re-signed ad hoc (Apple silicon refuses an edited
# bundle). Its Resources/app makes it safe to keep in the Dock: opened on
# its own it runs scripts/mac/launch.sh; started by the launcher (LH_DEV_URL
# set) it loads this clone's electron/main.cjs.
#
#   zsh scripts/mac/brand-electron.sh <repo> <target .app>
#
# Run it from Terminal (install-launcher.sh does): macOS only lets apps
# with App Management permission write into app bundles, so the launcher
# itself never edits one.

set -eu
REPO="$1"
TARGET="$2"
SOURCE="$REPO/node_modules/electron/dist/Electron.app"
[[ -d "$SOURCE" ]] || { echo "No Electron.app in $REPO/node_modules: run npm install first." >&2; exit 1; }

rm -rf "$TARGET"
ditto "$SOURCE" "$TARGET"
cp "$REPO/build/icon.icns" "$TARGET/Contents/Resources/electron.icns"
mkdir -p "$TARGET/Contents/Resources/app"
printf '{ "name": "learnharness-dock", "main": "main.cjs" }\n' > "$TARGET/Contents/Resources/app/package.json"
cat > "$TARGET/Contents/Resources/app/main.cjs" <<JS
// Written by scripts/mac/brand-electron.sh.
const REPO = $(node -p "JSON.stringify(process.argv[1])" "$REPO");
if (process.env.LH_DEV_URL || process.argv.includes("--browser-service")) {
	require(REPO + "/electron/main.cjs");
} else {
	const { app } = require("electron");
	require("node:child_process").spawn(REPO + "/scripts/mac/launch.sh", [], { detached: true, stdio: "ignore" }).unref();
	app.dock?.hide();
	app.quit();
}
JS
PLIST="$TARGET/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName LearnHarness" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName LearnHarness" "$PLIST" 2>/dev/null \
	|| /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string LearnHarness" "$PLIST"
codesign --force --deep --sign - "$TARGET"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$TARGET" >/dev/null 2>&1 || true
# The launcher reads this to say when a new Electron needs a rebuild.
mkdir -p "$HOME/Library/Application Support/LearnHarness"
node -p "require('$REPO/node_modules/electron/package.json').version" > "$HOME/Library/Application Support/LearnHarness/launcher-electron-version"
echo "built $TARGET"
