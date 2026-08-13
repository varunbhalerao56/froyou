#!/usr/bin/env bash
# Regenerates the iOS launch screen: the froyou wordmark on the Paper surface.
#
# The mark is drawn from the font rather than cut out of assets/brand/froyou.png.
# The icon artwork is a pink wordmark on a pink gradient, so there is no clean
# edge to key against — extracting it would carry a halo of background with it.
# Setting the same glyphs in the same face costs nothing and gives a real alpha
# channel. It is SF Pro Rounded Bold: the artwork's ink box is 1581x487, aspect
# 3.246, and Bold measures 3.234 — the other three weights are 3.13 or below.
#
# The background stays the Paper preset's surfaces rather than the icon's pink.
# That is deliberate: those are the exact pixels the first Flutter frame paints,
# so the handover from storyboard to Flutter has nothing to give it away. A pink
# launch screen would snap to cream on every cold start.
#
# flutter_native_splash still writes the storyboard and the light/dark colour
# set; it is only its *images* we replace. It treats the source as @4x and
# downsamples with Interpolation.average, a box filter, which on @3x's x0.75
# ratio softens the letterforms. So it gets a 4x master and its three outputs
# are then overwritten with Lanczos resamples.
#
# Run from the repo root. Needs ImageMagick (brew install imagemagick).
set -euo pipefail

cd "$(dirname "$0")/.."

FONT="fonts/SF-Pro-Rounded-Bold.otf"
STAGE="build/splash"
OUT="ios/Runner/Assets.xcassets/LaunchImage.imageset"

# The wordmark's colour, sampled from the densest glyph pixels in froyou.png.
INK="#F3A8FF"

# The launch mark at @1x, in points, and how much of that square the word fills.
# 300 x 0.72 puts the word at ~216pt — a little over half the width of the
# narrowest iPhone, which is where a wordmark sits without becoming a poster.
BASE=300
FILL=0.72

command -v magick >/dev/null || { echo "needs ImageMagick (brew install imagemagick)"; exit 1; }
[ -f "$FONT" ] || { echo "missing $FONT"; exit 1; }

mkdir -p "$STAGE"

MASTER_PX=$((BASE * 4))
WORD_PX=$(printf "%.0f" "$(echo "$MASTER_PX * $FILL" | bc -l)")

echo "setting wordmark → ${WORD_PX}px wide on a ${MASTER_PX}px canvas"
magick -background none -fill "$INK" -font "$FONT" -pointsize 800 label:froyou \
  -trim +repage \
  -filter Lanczos -resize "${WORD_PX}x" \
  -background none -gravity center -extent "${MASTER_PX}x${MASTER_PX}" \
  -strip "$STAGE/splash-master.png"

echo "generating launch screen"
dart run flutter_native_splash:create

# Overwrite what the package just resampled.
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
