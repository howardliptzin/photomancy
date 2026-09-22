#!/bin/bash
#
# Does the ink land where the geometry says?
#
# The tests prove `pageTransform` maps rectangles exactly and that the renderer
# fills the rectangles it is handed. Neither proves the two are wired together,
# or that Quartz puts a photograph where the rectangle is — a sheet can be a
# half-cell out and still pass every arithmetic test in the suite.
#
# So: render real photographs through the real print path, rasterise the PDF at
# 300 ppi, find each photograph's edges in the pixels, and compare them with the
# window's rectangles under the transform. Run at three shapes, because the ones
# that go wrong are the extremes: 5 x 4 at a 12 px gap, 8 x 8 at 1 px, and 3 x 2
# on black.
#
# Edges are found by rendering each page twice — with the photographs and with
# background alone — and taking every pixel that differs, which is what makes
# the measurement work on a black sheet.
#
# Two numbers come out. "worst edge" is how far any photograph's edge sits from
# where it should; on a correct render it is about 1.2 px, which is pixel
# quantisation plus Quartz's edge antialiasing, or 0.11 mm. "stray" is ink
# anywhere outside the photographs' own rectangles, and on a correct render it
# is zero — that is the sharp one. For scale, displacing every photograph by
# half a point (0.18 mm) takes worst edge to 2.8 px and stray to several
# thousand.
#
#   ./Scripts/verify-print.sh [photo-folder] [--out <dir>]

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

PHOTOS=${1:-TestPhotos}
shift 2>/dev/null || true

BENCH=build/DerivedData/Build/Products/Release/photomancy-bench

printf '\033[1mBuilding the bench…\033[0m\n'
if ! xcodegen generate --quiet > build/last-verify-print.log 2>&1; then
    printf '\033[31mCould not generate the project.\033[0m\n'; cat build/last-verify-print.log; exit 2
fi
if ! xcodebuild -project Photomancy.xcodeproj -scheme photomancy-bench \
        -configuration Release -derivedDataPath build/DerivedData build \
        >> build/last-verify-print.log 2>&1; then
    printf '\033[31mBuild failed.\033[0m\n'
    grep -E " error:" build/last-verify-print.log | head -20
    echo "Full log: build/last-verify-print.log"
    exit 2
fi

printf '\n'
"$BENCH" --verify-print "$PHOTOS" "$@"
RESULT=$?

if [ $RESULT -eq 0 ]; then
    printf '\033[32m%s\033[0m\n' "the printed sheet is the sheet on screen"
else
    printf '\033[31m%s\033[0m\n' "the printed sheet is NOT the sheet on screen"
fi
exit $RESULT
