# Onboarding illustrations

Four drawings from [unDraw](https://undraw.co), one per intro page that has one.
unDraw is free for commercial and personal use and requires no attribution
([licence](https://undraw.co/license)); this file exists so the originals can be
traced, re-fetched or swapped, not because credit is owed.

| File | unDraw slug | Page |
|---|---|---|
| `reflection.svg` | `through-the-window_vqvx` | Say what's on your mind. |
| `on-device.svg` | `private-data_934y` | Everything stays on this device. |
| `companion.svg` | `thoughts_wy7s` | A companion, not a replacement. |
| `first-log.svg` | `recording_1q6x` | Try your first log. |

`reflection` opens the intro because it is the app icon as a scene — a figure at
a lit window with a flower field behind the glass. The fourth page, where you
pick your backdrops, deliberately has no drawing: the pictures it is asking for
are the ones that belong on it.

## These are not standalone SVGs

Every fill has been rewritten to a role — `__INK__`, `__MUTED__`,
`__SURFACE__`, `__ACCENT__` and so on. No renderer will open these files, and
that is intentional: `lib/core/ui/illustration.dart` resolves the roles against
the live palette on every build, so one asset serves all seven presets in both
brightnesses and stays legible in all fourteen. Dropped in as authored they
would break twice — unDraw draws on white, so the near-white fills become glare
on a dark surface and the near-black figures vanish into it, and `#6c63ff`
belongs to no preset here.

The ramp is anchored at `background` and `textPrimary` rather than at black and
white, which is the whole trick: those two have already swapped by the time dark
mode resolves, so the drawing inverts with the page for free.

## Changing them

Edit the list in `tool/fetch_illustrations.sh` and re-run it. The script fails
rather than ships if a drawing turns out to use a colour the table doesn't know,
because an unmapped literal renders as a hole in dark mode and nowhere else.

```bash
./tool/fetch_illustrations.sh            # refetch + tokenize
./tool/fetch_illustrations.sh --preview  # + rasterize both brightnesses
```

The slugs carry a hash that changes when the artist revises a drawing, so
pinning them is what keeps a refetch reproducible — and what makes a 404 the
signal that the original moved.
