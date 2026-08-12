#!/usr/bin/env bash
# Regenerates the iOS launch screen from assets/brand/splash-mark.svg.
#
# Same argument as the app icon, for the same reason: only the largest size is
# rasterized from vector and the smaller two are Lanczos downsamples of it. The
# bezel's outer rim is a 3px stroke on a 1024 canvas, so at @1x it is under a
# pixel wide — rendering the SVG at that size drops it, and the rim is most of
# what reads as a window.
#
# flutter_native_splash is still what writes the storyboard and the light/dark
# background colour set; it is only its *images* we replace. It treats the
# source as @4x and downsamples with Interpolation.average, a box filter, which
# on a non-integer ratio (@3x is x0.75) softens exactly that rim. So it gets a
# 4x master, and then the three PNGs it produced are overwritten with proper
# resamples.
#
# Run from the repo root. Needs ImageMagick (brew install imagemagick).
set -euo pipefail

cd "$(dirname "$0")/.."

SRC="assets/brand/splash-mark.svg"
STAGE="build/splash"
OUT="ios/Runner/Assets.xcassets/LaunchImage.imageset"

# The mark at @1x, in points. The porthole occupies 520/1024 of the canvas
# width, so 300 puts it at ~152x204pt — a bit over a third of the narrowest
# iPhone, which is where a launch mark sits without becoming a poster.
BASE=300

command -v magick >/dev/null || { echo "needs ImageMagick (brew install imagemagick)"; exit 1; }

mkdir -p "$STAGE"

echo "rendering $SRC → $((BASE * 4))px master"
swift tool/svg2png.swift "$SRC" "$STAGE/splash-master.png" "$((BASE * 4))"

echo "generating launch screen"
dart run flutter_native_splash:create

# Overwrite what the package just resampled. @3x comes from the master rather
# than from vector for the sub-pixel reason above.
echo "resampling @3x/@2x/@1x"
for spec in "LaunchImage@3x:3" "LaunchImage@2x:2" "LaunchImage:1"; do
  name="${spec%%:*}"
  px=$((BASE * ${spec##*:}))
  magick "$STAGE/splash-master.png" -filter Lanczos -resize "${px}x${px}" \
    -strip "$OUT/$name.png"
done

echo "wrote $(ls "$OUT"/LaunchImage*.png | wc -l | tr -d ' ') PNGs to $OUT"

# Two things the package leaves behind, both cosmetic and both re-done on every
# run — so they are corrected here rather than by hand.

# It rewrites Info.plist through its own serializer, which indents the root dict
# one level deeper than Xcode does and turns a one-key edit into a whole-file
# diff. plutil re-emits it in Apple's own format, which is what the file was in
# to begin with.
echo "normalising Info.plist"
plutil -convert xml1 ios/Runner/Info.plist

# The storyboard records the launch image's natural size for Interface Builder.
# The package writes the *master's* pixel size there, so it claims a 1200pt mark
# on a 390pt phone. Nothing reads it at runtime — the size comes from the asset
# catalog — but it is wrong, and it is what anyone opening the storyboard sees.
echo "correcting storyboard image size to ${BASE}pt"
sed -i '' \
  -e "s|<image name=\"LaunchImage\" width=\"[0-9.]*\" height=\"[0-9.]*\"/>|<image name=\"LaunchImage\" width=\"$BASE\" height=\"$BASE\"/>|" \
  ios/Runner/Base.lproj/LaunchScreen.storyboard

echo
echo "note: LaunchScreen.storyboard and the background colour set are"
echo "      generated too — both are checked in, so review the diff."
