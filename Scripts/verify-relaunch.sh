#!/bin/bash
#
# The M1 acceptance test, and the only one that means anything.
#
# An in-process test cannot prove that security-scoped bookmarks work: once a
# URL has been resolved it stays authorised for the life of the process, so the
# test passes even when the bookmarks are broken. It measures the proxy.
#
# This measures the thing. Import, quit, DELETE THE THUMBNAIL CACHE, relaunch.
# The cache deletion is the part people leave out — without it the photographs
# render on second launch from cached thumbnails whether or not a single
# bookmark still resolves, and the test is worthless.
#
#   ./Scripts/verify-relaunch.sh [path/to/Photomancy.app] [photo-directory]

set -uo pipefail

APP=${1:-build/DerivedData/Build/Products/Debug/Photomancy.app}
PHOTO_DIR=${2:-TestPhotos}
BUNDLE_ID=com.luna-park.Photomancy
CONTAINER="$HOME/Library/Containers/$BUNDLE_ID/Data/Library/Application Support/Photomancy"
LIBRARY="$CONTAINER/library.json"
THUMBNAILS="$CONTAINER/Thumbnails"

red()   { printf '\033[31m%s\033[0m\n' "$1"; }
green() { printf '\033[32m%s\033[0m\n' "$1"; }
step()  { printf '\n\033[1m%s\033[0m\n' "$1"; }

[ -d "$APP" ] || { red "no app at $APP — build it first"; exit 2; }
# `open -a` needs an absolute path.
APP=$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")

shopt -s nullglob
PHOTOS=("$PHOTO_DIR"/*.[jJ][pP][gG] "$PHOTO_DIR"/*.[jJ][pP][eE][gG] \
        "$PHOTO_DIR"/*.[hH][eE][iI][cC] "$PHOTO_DIR"/*.[pP][nN][gG])
shopt -u nullglob
[ ${#PHOTOS[@]} -gt 0 ] || { red "no photographs in $PHOTO_DIR"; exit 2; }

quit_app() {
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1
    for _ in $(seq 1 40); do
        pgrep -f "$APP/Contents/MacOS/Photomancy" >/dev/null || return 0
        sleep 0.25
    done
    pkill -f "$APP/Contents/MacOS/Photomancy" >/dev/null 2>&1
    sleep 1
}

reference_count() {
    [ -f "$LIBRARY" ] || { echo 0; return; }
    python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))['references']))" "$LIBRARY" 2>/dev/null || echo 0
}

# The clean slate below deletes the app's whole library — every collection, pin
# and setting. Refuse to do that to a real one unless it has been asked for.
EXISTING=$(reference_count)
if [ "$EXISTING" -gt 0 ] && [ "${PHOTOMANCY_WIPE_LIBRARY:-}" != 1 ]; then
    red "This would delete the app's library, which holds $EXISTING photographs."
    echo "Back up the container's Data folder first, for example:"
    echo "  ditto \"$HOME/Library/Containers/$BUNDLE_ID/Data\" ~/Photomancy-Data-backup"
    echo "then run again with PHOTOMANCY_WIPE_LIBRARY=1, and put the backup back afterwards."
    exit 2
fi

step "0 · Clean slate"
quit_app
rm -rf "$HOME/Library/Containers/$BUNDLE_ID"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
echo "container removed, app registered"
echo "${#PHOTOS[@]} photographs to import"

step "1 · First launch — import through Open With"
open -a "$APP" "${PHOTOS[@]}"
for _ in $(seq 1 60); do
    [ "$(reference_count)" -eq "${#PHOTOS[@]}" ] && break
    sleep 0.5
done
IMPORTED=$(reference_count)
echo "library.json holds $IMPORTED references"
[ "$IMPORTED" -eq "${#PHOTOS[@]}" ] || { red "import did not complete"; quit_app; exit 1; }
sleep 4   # let the grid draw and the thumbnail cache fill
echo "thumbnail cache: $(ls "$THUMBNAILS" 2>/dev/null | wc -l | tr -d ' ') entries"

step "2 · Quit"
quit_app
pgrep -f "$APP/Contents/MacOS/Photomancy" >/dev/null && { red "still running"; exit 1; }
echo "process gone"

step "3 · Delete the thumbnail cache"
# Without this the next launch could render entirely from cache and prove
# nothing about the bookmarks.
rm -rf "$THUMBNAILS"
echo "thumbnail cache: $(ls "$THUMBNAILS" 2>/dev/null | wc -l | tr -d ' ') entries"

step "4 · Relaunch, with no files passed"
START=$(date '+%Y-%m-%d %H:%M:%S')
open -a "$APP"
sleep 12

CHECK=$(/usr/bin/log show --predicate "subsystem == \"$BUNDLE_ID\"" --start "$START" --style compact 2>/dev/null \
        | grep -E "access check|thumbnails:|launched with" | sed 's/^[^ ]* [^ ]* *//')
echo "$CHECK"

OPENED=$(printf '%s\n' "$CHECK" | grep -o 'access check: [0-9]* of [0-9]*' | head -1 | awk '{print $3}')
TOTAL=$(printf '%s\n' "$CHECK" | grep -o 'access check: [0-9]* of [0-9]*' | head -1 | awk '{print $5}')
DECODED=$(printf '%s\n' "$CHECK" | grep -o '[0-9]* decoded from originals' | head -1 | awk '{print $1}')
FAILED=$(printf '%s\n' "$CHECK" | grep -c 'access check failed')
AFTER=$(ls "$THUMBNAILS" 2>/dev/null | wc -l | tr -d ' ')

step "Result"
quit_app

if [ "${OPENED:-0}" -eq "${#PHOTOS[@]}" ] && [ "${TOTAL:-0}" -eq "${#PHOTOS[@]}" ] \
   && [ "${DECODED:-0}" -gt 0 ] && [ "$FAILED" -eq 0 ]; then
    green "PASS — $OPENED of $TOTAL photographs reopened through their bookmarks"
    green "       $DECODED thumbnails decoded from the originals, not from cache"
    green "       cache rebuilt to $AFTER entries"
    exit 0
fi

red "FAIL — opened ${OPENED:-?} of ${TOTAL:-?}, decoded ${DECODED:-?}, access failures $FAILED"
exit 1
