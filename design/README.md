# thru design files

Source files for the thru wordmark, the mood face and the README visuals. The rules behind them are in the
[thru design system](https://claude.ai/artifact/11uT4DxLLf4UCY2wVuzKxD) doc.

## What is here

| Folder | Contents |
| --- | --- |
| `source/` | Bash build scripts (`build-*.sh`) that write SVG sources (`*.src.svg`), shared helpers in `lib.sh`, and VectorCraft documents (`*.vectorcraft`) for the visuals that needed effects |
| `source/parts/` | Vector parts: the wordmark masters and every earlier version, the eased t foot and u bowl paths, watch parts and grain |
| `sheets/` | Exploration and construction sheets as PNG, from the first heart and font studies to the final wordmark |
| `lab/` | Two interactive pages: `mood-face.html` (recovery score drives the face) and `bowl.html` (curvature combs for the t foot and u bowl) |
| `assets/` | The app icon and framed screenshots the build scripts read |

## The wordmark

The master is `source/parts/wordmark-geo.svg`: one path, 405 x 180 units, baseline at 180.

- Grid: one cell is the t's top square (30), split into 15 and 7.5. Stems and bars are 30.
- Widths: t 75, h 105, r 75, u 105, letters 15 apart.
- The cut runs from 90 to 120 through every letter.
- h arch: top half of a circle 75 across. r arm: quarter of a circle 60 across plus a 15 bar.
- t foot: eased curve (ease 0.25). u bowl: eased outer edge from the cut, inner edge exactly 30 inside it.

`sheets/final.png` shows the construction. Earlier masters are kept as `parts/wordmark-geo-v*.svg` and
`parts/wordmark-baseline.svg`. Study scripts read the version they were drawn on (for example `build-geo.sh` reads
`v7`), so every sheet can be rebuilt as it was; `build-final.sh` reads the current master.

## Rebuilding

Run a build script from `source/` to regenerate its `.src.svg`, for example:

```bash
cd design/source && bash build-final.sh
```

The scripts need only Bash and awk. Turning a `.src.svg` into a PNG, and the glass shadow and glow on cards,
were done in VectorCraft: open the `.src.svg`, select the white cards, add a drop shadow and an inner glow, and
export SVG (text as outlines) and PNG. The `.vectorcraft` files keep those edits for the hero, watch and wordmark
sheets.

## The lab pages

The pages are plain HTML with no build step. To serve them locally on Windows:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File design/lab/serve.ps1
```

Then open `http://localhost:8765/mood-face.html` or `http://localhost:8765/bowl.html`.

The mood face page still uses the previous u (112.5 wide); rebuild it on the final u before using it as a reference.
