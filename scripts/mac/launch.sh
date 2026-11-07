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
#     would show as "Electron" with Electron's icon. Rename it and give it
#     the LearnHarness icon (redone after each npm install, which resets it),
#     then re-sign it ad hoc, since Apple silicon refuses an edited bundle.
ELECTRON_APP="$REPO/node_modules/electron/dist/Electron.app"
PLIST="$ELECTRON_APP/Contents/Info.plist"
if [[ -f "$PLIST" && "$(/usr/libexec/PlistBuddy -c "Print :CFBundleName" "$PLIST" 2>/dev/null)" != "LearnHarness" ]]; then
	cp "$REPO/build/icon.icns" "$ELECTRON_APP/Contents/Resources/electron.icns"
	/usr/libexec/PlistBuddy -c "Set :CFBundleName LearnHarness" "$PLIST"
	/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName LearnHarness" "$PLIST" 2>/dev/null \
		|| /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string LearnHarness" "$PLIST"
	codesign --force --deep --sign - "$ELECTRON_APP" || echo "codesign failed"
	touch "$ELECTRON_APP"
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$ELECTRON_APP" >/dev/null 2>&1 || true
	echo "branded Electron.app"
fi

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
	LH_DEV_URL="$URL" "$REPO/node_modules/.bin/electron" "$REPO" >>"$LOG" 2>&1
	pkill -f "$REPO/node_modules/" 2>/dev/null
) </dev/null >/dev/null 2>&1 &
disown
echo "started"
