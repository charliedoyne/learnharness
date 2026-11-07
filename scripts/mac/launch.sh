#!/bin/zsh -l
#
# Start (or restart) LearnHarness from this clone, on the latest code.
# The desktop icon made by install-launcher.sh runs this; it also works
# from a terminal: scripts/mac/launch.sh
#
#   1. stops a running copy started from this clone
#   2. pulls the latest main from origin (skipped, with a notice, if the
#      clone has local changes or no network)
#   3. runs npm install when package-lock.json changed
#   4. starts Next, waits for it, then opens the window; closing the window
#      quits it
#
# Data and keys stay where they always were (Application Support), so a
# restart or an update never touches what you learned.
# Log: ~/Library/Logs/LearnHarness/launcher.log

set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SUPPORT="$HOME/Library/Application Support/LearnHarness"
LOG_DIR="$HOME/Library/Logs/LearnHarness"
LOG="$LOG_DIR/launcher.log"
mkdir -p "$LOG_DIR" "$SUPPORT"
exec >>"$LOG" 2>&1
echo "── $(date) ── launching from $REPO"

notify() { osascript -e "display notification \"$1\" with title \"LearnHarness\"" >/dev/null 2>&1 || true; }
fail() { osascript -e "display alert \"LearnHarness could not start\" message \"$1

Details: $LOG\"" >/dev/null 2>&1 || true; exit 1; }

export LH_DATA_DIR="$SUPPORT/data"
export LH_AUTH_FILE="$SUPPORT/auth.json"

# A double-clicked app gets a bare PATH: add the usual Node installs.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
[[ -s "$HOME/.nvm/nvm.sh" ]] && source "$HOME/.nvm/nvm.sh" >/dev/null 2>&1
command -v npm >/dev/null || fail "npm was not found. Install Node.js (https://nodejs.org) and try again."
cd "$REPO" || fail "The LearnHarness folder is missing: $REPO"

# 1. Stop a copy already running from this clone (Next dev, Electron and
#    concurrently all run from this clone's node_modules).
if pkill -f "$REPO/node_modules/" ; then
	echo "stopped the running copy"
	for _ in {1..20}; do pgrep -f "$REPO/node_modules/" >/dev/null || break; sleep 0.5; done
	pkill -9 -f "$REPO/node_modules/" 2>/dev/null
fi

# 2. Latest code.
lock_before="$(shasum package-lock.json 2>/dev/null)"
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
	notify "Local changes in the code folder, so updates were skipped this time."
	echo "skipped pull: local changes"
elif git pull --ff-only origin main; then
	echo "now at $(git log --oneline -1)"
else
	notify "Couldn't fetch updates; starting the version you have."
fi

# 3. Dependencies, only when they changed.
if [[ ! -d node_modules || "$(shasum package-lock.json 2>/dev/null)" != "$lock_before" ]]; then
	notify "Installing updates, this can take a minute…"
	npm install || fail "npm install failed."
fi

# 3b. The dev window runs the stock Electron.app from node_modules, which
#     shows as "Electron" in the Dock (the Dock names a running app after
#     its bundle folder). Keep a renamed copy, LearnHarness.app, with the
#     LearnHarness icon, rebuilt whenever npm installs a new Electron, and
#     re-signed ad hoc since Apple silicon refuses an edited bundle.
#     Its Resources/app makes the copy safe to keep in the Dock: opened on
#     its own it runs this launcher; opened by this launcher it loads
#     LearnHarness's electron/main.cjs.
DIST="$REPO/node_modules/electron/dist"
BRANDED="$DIST/LearnHarness.app"
STAMP="$BRANDED/Contents/lh-electron-version"
BRAND_REV=2 # bump when the branded copy's contents change
ELECTRON_VERSION="$(node -p "require('$REPO/node_modules/electron/package.json').version" 2>/dev/null)-$BRAND_REV-$REPO"
if [[ -d "$DIST/Electron.app" && "$(cat "$STAMP" 2>/dev/null)" != "$ELECTRON_VERSION" ]]; then
	rm -rf "$BRANDED"
	ditto "$DIST/Electron.app" "$BRANDED"
	PLIST="$BRANDED/Contents/Info.plist"
	cp "$REPO/build/icon.icns" "$BRANDED/Contents/Resources/electron.icns"
	mkdir -p "$BRANDED/Contents/Resources/app"
	printf '{ "name": "learnharness-dock", "main": "main.cjs" }\n' > "$BRANDED/Contents/Resources/app/package.json"
	cat > "$BRANDED/Contents/Resources/app/main.cjs" <<JS
// Written by scripts/mac/launch.sh.
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
	/usr/libexec/PlistBuddy -c "Set :CFBundleName LearnHarness" "$PLIST"
	/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName LearnHarness" "$PLIST" 2>/dev/null \
		|| /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string LearnHarness" "$PLIST"
	codesign --force --deep --sign - "$BRANDED" || echo "codesign failed"
	echo "$ELECTRON_VERSION" > "$STAMP"
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$BRANDED" >/dev/null 2>&1 || true
	echo "built LearnHarness.app from Electron $ELECTRON_VERSION"
fi
ELECTRON_BIN="$BRANDED/Contents/MacOS/Electron"
[[ -x "$ELECTRON_BIN" ]] || ELECTRON_BIN="$REPO/node_modules/.bin/electron"

# 4. Start, detached from this script. Next first; the window only once
#    the first page has compiled (Electron's dev shell loads its URL once,
#    so an early window stays blank). Closing the window stops Next.
notify "Starting… the window opens when it's ready (first start can take a minute)."
URL="http://localhost:3000"
(
	"$REPO/node_modules/.bin/next" dev >>"$LOG" 2>&1 &
	for _ in {1..90}; do
		curl -s -o /dev/null --max-time 180 "$URL" && break
		sleep 2
	done
	LH_DEV_URL="$URL" "$ELECTRON_BIN" "$REPO" >>"$LOG" 2>&1
	pkill -f "$REPO/node_modules/" 2>/dev/null
) </dev/null >/dev/null 2>&1 &
disown
echo "started"
