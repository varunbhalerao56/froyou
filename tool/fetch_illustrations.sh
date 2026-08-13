#!/usr/bin/env bash
# Refetches the onboarding illustrations from unDraw and tokenizes their palette.
#
# unDraw art is authored on white with one swappable accent (#6c63ff) and a
# fixed set of greys, inks and skin tones. Dropped in as-is it breaks twice
# here: on a dark surface the near-white fills become glare and the near-black
# figures disappear, and #6c63ff belongs to none of the seven presets.
#
# So nothing is drawn in a literal colour. Every fill is rewritten to a role —
# __INK__, __MUTED__, __SURFACE__ … — and lib/core/ui/illustration.dart resolves
# those against the live palette on every build. That is what lets one asset
# serve 7 presets x 2 brightnesses and stay legible in all fourteen.
#
# The output is deliberately NOT a standalone SVG: the tokens are not colours
# and no renderer will open the file. Preview with --preview, which substitutes
# a sample palette and rasterizes through tool/svg2png.swift.
#
#   ./tool/fetch_illustrations.sh            # refetch + tokenize
#   ./tool/fetch_illustrations.sh --preview  # + write previews to build/
#
# Licence: unDraw is free for commercial and personal use with no attribution
# required (https://undraw.co/license). assets/illustrations/README.md records
# which slugs these are so they can be traced back or swapped.
set -euo pipefail

cd "$(dirname "$0")/.."

OUT="assets/illustrations"
PREVIEW=${1:-}

# name -> unDraw CDN path. The slug carries a hash that changes when the artist
# revises the drawing, so pinning it is what keeps a refetch reproducible.
ILLUSTRATIONS=(
  "reflection:https://cdn.undraw.co/illustrations/through-the-window_vqvx.svg"
  "on-device:https://cdn.undraw.co/illustration/private-data_934y.svg"
  "companion:https://cdn.undraw.co/illustrations/thoughts_wy7s.svg"
  "first-log:https://cdn.undraw.co/illustration/recording_1q6x.svg"
)

# Every literal unDraw uses, mapped to the role it plays. Ordered dark to light
# within a role only for readability — the substitution is exact-match per
# colour, so order does not matter here. It matters a great deal in `tokenize`.
declare -a PALETTE=(
  "6c63ff:__ACCENT__"       # the one colour unDraw intends you to replace
  "ff6584:__ACCENT_SOFT__"  # its secondary pink — a sun, a heart

  "090814:__INK__"          # darkest structure: hair, shoes, outlines
  "2f2e41:__INK__"
  "3f3d56:__INK_SOFT__"     # a step lighter: trousers, frames

  "9e616a:__SKIN_DEEP__"    # shadowed skin. Kept apart from __SKIN__ or a face
  "a0616a:__SKIN_DEEP__"    # and the arm below it merge into one flat shape.
  "ed9da0:__SKIN__"
  "ffb6b6:__SKIN__"
  "ffb8b8:__SKIN__"

  "cccccc:__MUTED__"        # mid greys: benches, waveforms, hairlines
  "cacaca:__MUTED__"
  "cbcbcb:__MUTED__"
  "d0cde1:__MUTED__"

  "e4e4e4:__SURFACE_DIM__"  # the shaded face of a light object
  "e6e6e6:__SURFACE_DIM__"

  "f0f0f0:__SURFACE__"      # the lit face
  "f2f2f2:__SURFACE__"

  "ffffff:__SURFACE_HI__"   # highlights, paper, a screen
)

# Rewrites one SVG in place. Two rules make this safe:
#
#  1. Shorthand is expanded first. #ccc and #cccccc mean the same colour but
#     only one of them is in the table, and a naive pass over the short form
#     would also eat the first four characters of every long one.
#  2. Hex is lowercased first, so the table needs one entry per colour rather
#     than one per spelling.
#
# Any literal left over after the pass is reported rather than shipped — a
# revised drawing that introduces a new grey would otherwise render as a hole
# in dark mode and nowhere else.
tokenize() {
  local file="$1" name="$2"

  python3 - "$file" "$name" "${PALETTE[@]}" <<'PY'
import re, sys

path, name, *pairs = sys.argv[1:]
table = dict(p.split(':') for p in pairs)

svg = open(path, encoding='utf-8').read()

def expand(m):
    h = m.group(1).lower()
    return '#' + (''.join(c * 2 for c in h) if len(h) == 3 else h)

svg = re.sub(r'#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b', expand, svg)

for literal, token in table.items():
    svg = svg.replace('#' + literal, token)

leftover = sorted(set(re.findall(r'#[0-9a-f]{6}\b', svg)))
if leftover:
    sys.exit(f'{name}: unmapped colour(s) {" ".join(leftover)} — add them to PALETTE')

open(path, 'w', encoding='utf-8').write(svg)
print(f'  {name}: {len(set(re.findall(r"__[A-Z_]+__", svg)))} roles')
PY
}

mkdir -p "$OUT"

for spec in "${ILLUSTRATIONS[@]}"; do
  name="${spec%%:*}"
  url="${spec#*:}"
  echo "fetching $name ← $(basename "$url")"
  curl -fsS --max-time 60 "$url" -o "$OUT/$name.svg"
  tokenize "$OUT/$name.svg" "$name"
done

echo "wrote $(ls "$OUT"/*.svg | wc -l | tr -d ' ') tokenized SVGs to $OUT"

# A tokenized file is not renderable, so there is no way to eyeball a bad fetch
# without putting a palette back. This substitutes the Paper preset at both
# brightnesses — the same ramp illustration.dart builds — and rasterizes.
if [[ "$PREVIEW" == "--preview" ]]; then
  command -v magick >/dev/null || { echo "preview needs ImageMagick"; exit 1; }
  mkdir -p build/illustration-preview

  for mode in light dark; do
    if [[ $mode == light ]]; then bg=F2EFE9; ink=14161A; accent=54637A; else bg=16181D; ink=F6F5F2; accent=9DB4D4; fi
    for f in "$OUT"/*.svg; do
      name=$(basename "$f" .svg)
      python3 - "$f" "/tmp/froyou-preview.svg" "$bg" "$ink" "$accent" <<'PY'
import sys
src, dst, bg, ink, accent = sys.argv[1:]

def mix(a, b, t):
    a = [int(a[i:i+2], 16) for i in (0, 2, 4)]
    b = [int(b[i:i+2], 16) for i in (0, 2, 4)]
    return '#%02x%02x%02x' % tuple(round(x + (y - x) * t) for x, y in zip(a, b))

# Must stay in step with _ramp in lib/core/ui/illustration.dart.
ramp = {
    '__SURFACE_HI__': 0.035, '__SURFACE__': 0.08, '__SURFACE_DIM__': 0.13,
    '__MUTED__': 0.22, '__SKIN__': 0.34, '__SKIN_DEEP__': 0.52,
    '__INK_SOFT__': 0.74, '__INK__': 1.0,
}
svg = open(src, encoding='utf-8').read()
for token, t in ramp.items():
    svg = svg.replace(token, mix(bg, ink, t))
svg = svg.replace('__ACCENT_SOFT__', mix(bg, accent, 0.55)).replace('__ACCENT__', '#' + accent)
open(dst, 'w', encoding='utf-8').write(svg)
PY
      swift tool/svg2png.swift /tmp/froyou-preview.svg \
        "build/illustration-preview/$name-$mode.png" 600
      magick "build/illustration-preview/$name-$mode.png" \
        -background "#$bg" -alpha remove -alpha off \
        "build/illustration-preview/$name-$mode.png"
    done
  done

  magick montage build/illustration-preview/*.png -background '#888888' \
    -label '%t' -tile 4x -geometry 460x460+10+10 -pointsize 20 \
    build/illustration-preview/sheet.png
  echo "previews → build/illustration-preview/sheet.png"
fi
