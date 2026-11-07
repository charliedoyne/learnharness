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
# The window's Electron runs from ~/Applications with this clone as its
# argument; Next and the helpers run from this clone's node_modules.
stop_running() {
	local a=1 b=1
	pkill "$@" -f "$REPO/node_modules/" && a=0
	pkill "$@" -f "LearnHarness.app/Contents/MacOS/Electron $REPO" && b=0
	(( a == 0 || b == 0 ))
}
if stop_running ; then
	echo "stopped the running copy"
	for _ in {1..20}; do pgrep -f "$REPO/node_modules/" >/dev/null || pgrep -f "LearnHarness.app/Contents/MacOS/Electron $REPO" >/dev/null || break; sleep 0.5; done
	stop_running -9 2>/dev/null
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

# 3b. The window runs as ~/Applications/LearnHarness.app (a renamed
#     Electron with the LearnHarness icon, built by install-launcher.sh
#     from Terminal). This script NEVER writes into an app bundle: macOS
#     blocks that for apps without App Management permission ("LearnHarness
#     was prevented from modifying apps"). Without the app, the stock
#     Electron runs (it shows as "Electron").
BRANDED="$HOME/Applications/LearnHarness.app"
ELECTRON_BIN="$BRANDED/Contents/MacOS/Electron"
if [[ -x "$ELECTRON_BIN" ]]; then
	built="$(cat "$HOME/Library/Application Support/LearnHarness/launcher-electron-version" 2>/dev/null)"
	current="$(node -p "require('$REPO/node_modules/electron/package.json').version" 2>/dev/null)"
	if [[ -n "$current" && "$built" != "$current" ]]; then
		notify "Electron was updated. Run scripts/mac/install-launcher.sh in Terminal once to refresh the app."
	fi
else
	ELECTRON_BIN="$REPO/node_modules/.bin/electron"
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
	LH_DEV_URL="$URL" "$ELECTRON_BIN" "$REPO" >>"$LOG" 2>&1
	pkill -f "$REPO/node_modules/" 2>/dev/null
) </dev/null >/dev/null 2>&1 &
disown
echo "started"
