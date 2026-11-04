# thru design system

The reference for redesigning the thru app around the geometric wordmark, the mood face and the salmon brand
colour. Everything derives from one grid: the t's top square. The live, illustrated copy of this document is the
[thru design system](https://claude.ai/artifact/11uT4DxLLf4UCY2wVuzKxD) doc; this file is the version for working in
the code, and wins where the two differ.

Pictures referred to below are in `design/sheets/` (construction: `final.png`, system overview: `system.png`,
brand colour: `coral.png`, icons: `icons.png`). Ready-made brand files are in `design/brand/`.

## Principles

thru should look built, not drawn: bars, squares and true circles on one grid, with a single cut that lets you see
through. Five rules decide every design choice.

1. **One grid.** Every size comes from the t's top square (the cell) and its halves and quarters. A value that is
   not on the grid needs a reason.
2. **Bars and circles only.** Shapes are rectangles, half circles, quarter circles and rings. Curves meet straight
   edges smoothly, and a bar keeps one width all the way round.
3. **See through.** The cut is the brand's signature: one horizontal band where the content shows through. Use it
   once per view (the wordmark or the face), never as decoration on components.
4. **Warm and calm.** Paper background, warm ink, soft colour glows. Colour carries meaning (recovery, sleep,
   training, food), never decoration.
5. **Explain every number.** Every score has its reason on the same screen, never hidden behind a tap the user
   cannot guess.

## Wordmark

Drawn, not typeset: four letters built from bars and circles on a square grid, with one horizontal cut through
every letter at the same height. **Locked; do not redraw it.**

Master: `design/source/parts/wordmark-geo.svg`, 405 x 180 units, baseline at 180. App-ready exports:
`design/brand/thru-wordmark-*.svg|png`.

| Rule | Value (master units) |
| --- | --- |
| Cell | 30 x 30, the t's top square; split into 15 and 7.5 for finer steps |
| Height | 180 (6 cells): h top 0, t top 30, x-height 60, cut 90 to 120, baseline 180 |
| Stems and bars | 30 everywhere |
| Widths | t 75, h 105, r 75, u 105; 15 between letters; total 405 |
| h arch | Top half of a circle 75 across, sitting on the x-height, touching the stems in a point |
| r arm | Quarter of a circle 60 across, then a 15 bar |
| t foot | Eased curve (ease 0.25) from the stem into the foot bar |
| u bowl | Eased outer edge starting at the cut; inner edge exactly 30 inside it, so the bar is 30 wide all round |

**Usage**

- Clear space: one third of the wordmark height on every side.
- Minimum size: 24 pt tall. Below that, use the mood face or the app icon.
- Versions: ink letters with a salmon u on paper (default); paper letters with a salmon u on dark; all ink; all
  paper; all white on a recovery or area colour. Never a gradient, outline or shadow on the letters.
- The cut is part of the letters: never fill it, move it or add a second one.
- In the app, ship the wordmark as a vector asset (PDF or SVG in the asset catalog, "Preserve Vector Data" on),
  made from `design/brand/thru-wordmark-salmon.svg` and `thru-wordmark-salmon-on-dark.svg`.

## Mood face

The u is a face: its two top bars are the eyes, the cut is the gap, and the bowl is the mouth. It is the app's
symbol and its main way to show how the day looks, at a glance and without reading a number.

**Geometry** (face box 105 x 120, origin top left; this is the u of the master moved by -300, -60):

| Part | Shape |
| --- | --- |
| Eyes | Two 30 x 30 squares at x 0 and x 75, y 0 to 30 |
| Gap | y 30 to 60, empty (the cut) |
| Smile | The u bowl, y 60 to 120: path in `design/source/parts/u-constant.txt`, translated by (-300, -60) |
| Flat | A bar 105 x 30 at y 75 to 105 |
| Frown | The smile flipped vertically inside the mouth band (y becomes 180 - y) |

In the app tile the face is 56% of the tile height, centred (see `design/source/build-brand.sh`, `icon()`).

| State | Eyes | Mouth | Tile colour | When |
| --- | --- | --- | --- | --- |
| Push | Open | Smile | push `#33B378` | Recovery in the push zone |
| Moderate | Open | Flat | moderate `#EDAB2E` | About your usual |
| Recover | Open | Frown | recover `#DB454C` | Below your usual |
| Asleep | Lower half of each eye, 15 tall | Smile | sleep `#9470F2` | Sleep screen, bedtime, alarm |
| Saved | One eye at half height (wink) | Smile | area colour of what was saved | Food logged, data synced |
| New record | Eyes as half circles, flat side down, like the h arch | Smile | strain `#2978F2` | A PR or a streak |

**Rules**

- Build every face from the final u only. No new shapes, no outlines, no gradients.
- States differ in shape, so they read in greyscale and for colour-blind users. Colour never carries meaning alone.
- The mouth morphs smoothly with the recovery score: frown, flat, smile. Implement it as a SwiftUI `Shape` with
  `animatableData`: resample the smile and the flat bar to the same number of points and interpolate (the frown is
  the mirrored pair). `design/lab/mood-face.html` shows the behaviour; it still uses an older, wider u, so take the
  shape from this file, not from the lab page.
- The face is paper on the tile colour. One face per screen at most: top of Today, the watch face and widgets,
  never inside list rows.
- Tile corner radius is 22.5% of the tile, the same as the app icon.

## Colour

The palette is the one already in the app (`Theme` and `Zone` in `HealthDashboard/Components.swift`); the redesign
keeps the values, switches the accent to salmon and tightens where each colour may be used.

| Token | Hex | SwiftUI (r, g, b) | Use |
| --- | --- | --- | --- |
| paper | `#F9F6ED` | 0.976, 0.965, 0.929 | Page background, the face on the icon |
| ink | `#2B1F1A` | 0.17, 0.12, 0.10 | All text and the wordmark; secondary text is ink at 60% |
| accent (salmon) | `#F07B62` | 0.94, 0.48, 0.38 | Brand: the u in the wordmark, the icon tile, one action per screen, links |
| glow red, orange, amber | `#E02E3D`, `#F78033`, `#FCC254` | as in `Theme.glow` | Soft background glows only, 14 to 18% opacity, never on text or controls |
| dark surface | `#1C1714` | 0.11, 0.09, 0.08 | Dark icon, dark mode surfaces |
| push | `#33B378` | as in `Zone` | Recovery push zone, Push face |
| moderate | `#EDAB2E` | as in `Zone` | Moderate zone, Moderate face |
| recover | `#DB454C` | as in `Zone` | Recover zone, Recover face |
| sleep | `#9470F2` | 0.58, 0.44, 0.95 | Sleep score, stages, Asleep face |
| strain | `#2978F2` | 0.16, 0.47, 0.95 | Day strain, workouts, New record face |
| heart | `#21A8BD` | 0.13, 0.66, 0.74 | HRV, resting HR, breathing |
| body | `#F29433` | 0.95, 0.58, 0.20 | Weight and body composition |
| nutrition | `#E3598F` | 0.89, 0.35, 0.56 | Food, intake, quality |
| air | `#6BBDDB` | 0.42, 0.74, 0.86 | Bedroom air and light |

**Rules**

- `Theme.accent` changes from coral (0.91, 0.33, 0.24) to salmon (0.94, 0.48, 0.38). If the code uses `.accentColor`, add an
  `AccentColor` colour set with the same value (the catalog has none yet).
- Salmon sits clearly apart from the recover red, so a salmon face never reads as a warning. Do not use salmon for
  zone or area meaning.
- Salmon is too light for regular white text: labels on salmon are ink, or white at 17 pt semibold and up.
- A screen has one area colour: Sleep is purple, Workouts blue, Nutrition pink. Recovery colours appear only where
  recovery is shown.
- Text never uses an area colour; numbers stay ink, with the colour beside them in a bar, dot or chart.
- On Today the background glows take the recovery colour, as the app already does.
- Charts use the area colour at full strength for the current value and at 35% for history.

## App icon

Done in PR 5 (`HealthDashboard/Assets.xcassets/AppIcon.appiconset`): paper face on salmon (light), salmon face on
`#1C1714` (dark), white face on black for iOS to tint (tinted). The watch uses the light icon. Sources:
`design/brand/AppIcon-1024*.svg`.

## Grid, spacing and type

At screen scale one cell is 24 pt, split into 12 and 6. Every size is a step on that ladder.

| Token | Value | Use |
| --- | --- | --- |
| cell | 24 pt | Screen margins, card padding, card corner radius, gap between cards |
| half | 12 pt | Label to value, chip padding, row spacing, bar thickness |
| quarter | 6 pt | Icon to text, chart bar gap, hairline offsets |
| double | 48 pt | Space above a section title, height of a tappable row |

Put these in one place in code (for example `enum Grid { static let cell: CGFloat = 24 ... }`) and replace literal
paddings and radii with them.

**Type.** UI text stays San Francisco so Dynamic Type, accessibility sizes and the system feel keep working. The
wordmark is the only custom lettering and appears only as the logo.

| Style | Font | Size / line | Use |
| --- | --- | --- | --- |
| Score | SF Pro Semibold, tabular figures | 48 / 48 | The one hero number per card |
| Title | SF Pro Semibold | 28 / 36 | Screen titles |
| Heading | SF Pro Semibold | 17 / 24 | Card titles |
| Value | SF Pro Semibold, tabular figures | 22 / 24 | Metrics in grids |
| Body | SF Pro Regular | 17 / 24 | Explanations, the why lines |
| Label | SF Pro Regular, ink 60% | 13 / 18 | Units, captions, axis labels |

- Numbers move from SF Rounded to SF Pro with tabular figures (`.monospacedDigit()`): rounded numbers fight the
  square wordmark.
- Sizes are at the default Dynamic Type size and scale with it (`relativeTo:`); layouts reflow, never clip.
- No more than three sizes on one card.

## Components

Keep the app's glass and paper, but make every component a clear bar, square or circle.

| Component | Now (in code) | Redesign rule |
| --- | --- | --- |
| Background | `AmbientBackground`: paper plus three soft glows | Keep. Glows stay behind content; Today tints them with recovery |
| Card | `glassCard`: radius 18, thin material, white 38%, white hairline, soft shadow | Radius 24, padding 24, gap 24. Keep material and hairline; one hero number per card |
| Score hero | `BlobCluster` (`Blobs.swift`): merged blobs for sleep, recovery and strain | On Today, replace with the mood face tile; the three part scores become three score bars beneath it |
| Score bar | Gradient sliders in Food yesterday | Flat 12 pt bar with half-circle ends: area colour for the value, ink 10% for the track, a 2 pt tick for the target |
| Chips and segmented controls | System capsules and pickers | Keep system controls; selected state uses ink, not accent |
| Charts | Swift Charts in area colours | Square-ended bars 6 pt apart, 1 pt grid lines at ink 8%, 13 pt labels; current value full colour, history 35% |
| Buttons | `glassButton`: Liquid Glass on iOS 26 | Keep Liquid Glass; one prominent button per screen, in accent |
| Tab bar | System: Today, Trends, Workouts, Nutrition, Info | Keep the five tabs and system glass; selected tint ink. Replace the Today heart icon with a mood face glyph |
| Why rows | Arrow icon plus coloured sentence | Ink text with a 6 pt dot in the zone colour; the number in Value style |

**Do not**

- Add other corner radii: only 24 (cards), 12 (chips, bars) and full circles.
- Put text on glows or on area colours, except paper on the mood face tile.
- Use the cut motif inside components; it belongs to the wordmark and the face.

## Screens

Each screen keeps its content and order; the redesign changes the hero, the hierarchy and the shapes. Work top to
bottom: Today first, because it sets the pattern.

| Screen | Keep | Change |
| --- | --- | --- |
| Today (`TodayView`, `TodayVisuals`) | Date title, the advice line, the why rows, Food yesterday, the sleep streak | Mood face tile replaces the blob; sleep, recovery and strain become three score bars beneath it; the advice line takes the Title style; why rows get zone dots |
| Sleep (`SleepDetailView`) | Day, Week, Month; the score ring; the markers; where the points went | Ring becomes a 12 pt ring with half-circle ends; markers a 2 x 3 grid of equal cards; point costs as a bar per marker |
| Trends (`TrendsView`, `TrendMetrics`) | Range picker, insights card, metric tiles | Tiles on a strict 2-column grid, one number and one sparkline each; insights in Heading style, not red text |
| Workouts (`WorkoutsView`, `TrainingViews`, `StrengthViews`) | Training summary, day strain chart, this week, strength list, workout detail | Strain chart in square bars on the cell grid; target band as a 12 pt translucent bar; strength rows with the value right aligned |
| Nutrition (`NutritionDetailView`) | Last 7 days, food quality, energy and protein charts | Food quality uses the standard score bar; over-limit items first with a recover dot instead of red bars |
| Info (`InfoView`, `Explanations`) | Explanations of every score | Each score page opens with its face or bar, then the formula in Body text |
| Watch (`HealthWatch`) and widgets | Day and alarm faces | The mood face is the complication (Push, Moderate or Recover, score beside it); Asleep face in the sleep window |

**Order of work**

1. Tokens in code: grid spacing, radii, salmon accent, type styles.
2. Mood face as a SwiftUI shape built from the final u, with the morph and the states.
3. Today.
4. Sleep and Trends.
5. Workouts and Nutrition.
6. Watch and widgets.
7. README visuals and App Store slides regenerated with the new wordmark and icon (`design/source/build-*.sh`).

## Motion, accessibility and copy

**Motion**

- The face blinks every 3 to 5 s on Today only, and winks for 0.9 s when something is saved.
- The mouth morphs over 0.6 s when the score changes; background glows fade over 0.8 s, as now.
- Nothing bounces or loops. With Reduce Motion on, all of this stops and states switch instantly.

**Accessibility**

- Text contrast at least 4.5:1 on paper and on cards; check ink 60% on the thinnest material.
- Every face, bar and ring has a VoiceOver label with the number and the zone, for example "Recovery 83, push".
- States never rely on colour alone: the face shape and the zone word carry the meaning too.
- Tap targets at least 44 pt; layouts reflow at the largest Dynamic Type sizes.

**Copy**

- Plain, short, second person: "Good day to push", not "Optimal readiness detected".
- Metric units and 24 h time throughout; no em dashes.
- Every number shows its reason on the same screen, in a why row or a short line under it.
- Screenshots and marketing images use demo data only, never real health data.

## Open questions

- Should the Push, Moderate and Recover faces replace the zone names in the UI, or sit beside them? Default: beside.
- Is 24 pt the right cell on the smallest iPhone, or should margins drop to 18 there?
- `docs/brand/logo/` still holds the old Instrument Sans wordmark; replace it with `design/brand/` files when the
  README visuals are regenerated.
