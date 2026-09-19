#!/bin/bash
#
# Build the current branch and run it.
#
# The quit is not politeness. `open` on an app that is already running simply
# brings the existing copy to the front, so without it you would be looking at
# the previous build with no sign that anything had changed.
#
#   ./Scripts/run.sh

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

APP="$PWD/build/DerivedData/Build/Products/Debug/Photomancy.app"
LOG="build/last-build.log"
BRANCH=$(git branch --show-current)

printf '\033[1mBuilding %s…\033[0m\n' "$BRANCH"
mkdir -p build
# The project file is generated and not tracked, so after a branch switch it
# still lists the files of the branch you left and the build fails on a file
# that is not there. Regenerating costs about a second.
if ! xcodegen generate --quiet > "$LOG" 2>&1; then
    printf '\033[31mCould not generate the project.\033[0m\n'
    cat "$LOG"
    exit 1
fi
if ! xcodebuild -project Photomancy.xcodeproj -scheme Photomancy \
        -configuration Debug -derivedDataPath build/DerivedData build > "$LOG" 2>&1; then
    printf '\033[31mBuild failed.\033[0m\n'
    grep -E "error:" "$LOG" | head -20
    echo "Full log: $LOG"
    exit 1
fi

osascript -e 'tell application id "com.luna-park.Photomancy" to quit' >/dev/null 2>&1
for _ in $(seq 1 40); do
    pgrep -f "$APP/Contents/MacOS/Photomancy" >/dev/null || break
    sleep 0.25
done
# A modal panel (print, save, a sheet) refuses the quit. Opening now would only
# front the old copy — the exact thing this script exists to prevent.
if pgrep -f "$APP/Contents/MacOS/Photomancy" >/dev/null; then
    printf '\033[31mThe running copy did not quit\033[0m — close any open panel in it and run again.\n'
    exit 1
fi

open "$APP"
printf '\033[32mRunning\033[0m %s · %s\n' "$BRANCH" "$(git log --oneline -1)"
