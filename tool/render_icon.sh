#!/usr/bin/env bash
# Regenerates the iOS app icon from assets/brand/froyou.png.
#
# The source is a 2000px raster wordmark, so unlike the previous vector mark
# there is no rasterization step — every size is a Lanczos downsample straight
# from the 2000, rather than a chain through the 1024. Resampling once from the
# largest original is strictly better than resampling twice; the old script only
# went via the 1024 because that was the only size that came from vector.
#
# Writes straight into the asset catalog. Run from the repo root.
set -euo pipefail

cd "$(dirname "$0")/.."

SRC="assets/brand/froyou.png"
OUT="ios/Runner/Assets.xcassets/AppIcon.appiconset"

command -v magick >/dev/null || { echo "needs ImageMagick (brew install imagemagick)"; exit 1; }
[ -f "$SRC" ] || { echo "missing $SRC"; exit 1; }

# size@scale pairs the catalog references, as pixels.
for spec in \
  "1024x1024@1x:1024" \
  "20x20@1x:20" "20x20@2x:40" "20x20@3x:60" \
  "29x29@1x:29" "29x29@2x:58" "29x29@3x:87" \
  "40x40@1x:40" "40x40@2x:80" "40x40@3x:120" \
  "60x60@2x:120" "60x60@3x:180" \
  "76x76@1x:76" "76x76@2x:152" \
  "83.5x83.5@2x:167"
do
  name="${spec%%:*}"
  px="${spec##*:}"
  magick "$SRC" -filter Lanczos -resize "${px}x${px}" \
    -strip -define png:color-type=6 "$OUT/Icon-App-${name}.png"
done

# The App Store will not accept an icon with an alpha channel, and neither will
# it accept one that merely has an opaque one — the channel has to be gone.
for f in "$OUT"/Icon-App-*.png; do
  magick "$f" -background white -alpha remove -alpha off -strip "$f"
done

echo "wrote $(ls "$OUT"/Icon-App-*.png | wc -l | tr -d ' ') PNGs to $OUT"
