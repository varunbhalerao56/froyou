#!/usr/bin/env bash
# Regenerates the iOS app icon from assets/brand/app-icon.svg.
#
# Only the 1024 is rasterized from vector; everything else is a Lanczos
# downsample of it. Re-rendering the SVG at 40px instead would put a 4px rim
# stroke and a 0.032-frequency turbulence field below one pixel each, and the
# rim — which is most of what reads as a window at that size — would simply not
# be drawn. Downsampling averages both into something that survives.
#
# Writes straight into the asset catalog. Run from the repo root.
set -euo pipefail

cd "$(dirname "$0")/.."

SRC="assets/brand/app-icon.svg"
OUT="ios/Runner/Assets.xcassets/AppIcon.appiconset"
MASTER="$OUT/Icon-App-1024x1024@1x.png"

command -v magick >/dev/null || { echo "needs ImageMagick (brew install imagemagick)"; exit 1; }

echo "rendering $SRC → 1024px"
swift tool/svg2png.swift "$SRC" "$MASTER" 1024

# size@scale pairs the catalog references, as pixels.
for spec in \
  "20x20@2x:40" "20x20@3x:60" "20x20@1x:20" \
  "29x29@1x:29" "29x29@2x:58" "29x29@3x:87" \
  "40x40@1x:40" "40x40@2x:80" "40x40@3x:120" \
  "60x60@2x:120" "60x60@3x:180" \
  "76x76@1x:76" "76x76@2x:152" \
  "83.5x83.5@2x:167"
do
  name="${spec%%:*}"
  px="${spec##*:}"
  magick "$MASTER" -filter Lanczos -resize "${px}x${px}" \
    -strip -define png:color-type=6 "$OUT/Icon-App-${name}.png"
done

# The App Store will not accept an icon with an alpha channel, and neither will
# it accept one that merely has an opaque one — the channel has to be gone.
for f in "$OUT"/Icon-App-*.png; do
  magick "$f" -background black -alpha remove -alpha off -strip "$f"
done

echo "wrote $(ls "$OUT"/Icon-App-*.png | wc -l | tr -d ' ') PNGs to $OUT"
