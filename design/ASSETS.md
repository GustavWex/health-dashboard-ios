# thru design assets

Every design part made for the redesign, where it lives and how the code uses it. The rules behind them are in
[`DESIGN-SYSTEM.md`](DESIGN-SYSTEM.md). Open [`app/preview.html`](app/preview.html) in a browser to see the app
assets at a glance.

## Already in the app's asset catalogs

Vector image sets (SVG, "Preserve Vector Data" on) in a `Brand` folder. Folder names are not namespaced, so use the
plain names. Template images take the foreground colour or tint.

| Asset name | Catalog | Rendering | What it is | Use |
| --- | --- | --- | --- | --- |
| `TabToday` | iPhone | template | Mood face glyph | Today tab |
| `TabTrends` | iPhone | template | Three rising bars | Trends tab |
| `TabWorkouts` | iPhone | template | Barbell from bars | Workouts tab |
| `TabNutrition` | iPhone | template | Bowl | Nutrition tab |
| `TabInfo` | iPhone | template | Circle with bar and dot | Info tab |
| `BadgeJournal`, `BadgeGoals`, `BadgeAir`, `BadgeScale`, `BadgeBed`, `BadgeHeart`, `BadgeLift`, `BadgeAlarm`, `BadgeFood` | iPhone | template | 14 pt glyphs | White on a 24 pt square of the area colour in Info rows (see the Info screen in the mockups) |
| `FaceSmile`, `FaceFlat`, `FaceFrown` | iPhone, watch | template | Mood face, 105 x 120 | Push, Moderate, Recover, where a static face is enough |
| `FaceAsleep`, `FaceWink`, `FaceRecord` | iPhone, watch | template | Mood face states | Sleep window, Saved, New record |
| `Wordmark` | iPhone | original | Ink letters with a salmon u; paper letters in dark mode | The logo, at least 24 pt tall |
| `WordmarkMono` | iPhone | template | Wordmark in one colour | White on a colour, or ink when salmon would clash |

```swift
// Tab bar (HealthDashboardApp.swift): replace the SF Symbols
.tabItem { Label("Today", image: "TabToday") }

// Info row badge
Image("BadgeBed").foregroundStyle(.white)
    .frame(width: 24, height: 24).background(ThruBrand.Colors.sleep)

// Static face on a tile (prefer MoodFaceTile below when the face must animate)
Image("FaceSmile").resizable().scaledToFit().foregroundStyle(ThruBrand.Colors.paper)

// Logo
Image("Wordmark").resizable().scaledToFit().frame(height: 24)
```

The widget targets (`HealthWidget`, `HealthWatchWidget`) have no asset catalog: draw the face there with
`MoodFaceShape`, which works on every target.

## Code-ready parts in `design/app/`

| File | What it is |
| --- | --- |
| [`app/swift/ThruBrand.swift`](app/swift/ThruBrand.swift) | Reference SwiftUI: `ThruBrand` tokens (colours, grid, radii, bar), `MoodFaceShape` (animatable mouth from frown through flat to smile, blink lid, four eye styles), `MoodFaceTile`, and `ThruBrand.mood(recovery:)`. Not in a target yet: move it into `Shared/` so the app, watch and widgets share it, then build once in Xcode (it was written without a compiler) |
| [`app/tokens.json`](app/tokens.json) | Every token from the design doc as data: colours (hex, rgb, use), opacities, grid, radii, bars, type styles, motion, face rules |
| [`app/mood-face-points.json`](app/mood-face-points.json) | The smile and flat mouth outlines, 242 matching points each, for any platform that needs the morph |
| `app/icons/*.svg` | Sources of the tab icons and badges above |
| `app/faces/*.svg` | Sources of the six faces above |

```swift
// The Today hero, animating with the score
MoodFaceTile(mood: ThruBrand.mood(recovery: score), color: zoneColor, lid: blinkLid)
    .frame(width: 112, height: 112)
    .animation(.easeInOut(duration: 0.6), value: score)
    .accessibilityLabel("Recovery \(Int(score)), \(zoneName)")
```

## Brand files in `design/brand/`

App icons (light, dark, tinted, already installed by PR 5), the mark, the lockup and every wordmark colourway, as
SVG and PNG. See [`brand/README.md`](brand/README.md).

## Visual references

| File | What it shows |
| --- | --- |
| [`lab/screens-mockup.html`](lab/screens-mockup.html) | Every screen in the chosen flat style: Today, Sleep, Trends, Workouts, workout detail, Nutrition, Info, a score explanation, watch faces and widgets. The main reference for layout, spacing and content |
| [`lab/today-mockup.html`](lab/today-mockup.html) | Today in the two card styles that were compared; B (flat) was chosen |
| [`lab/mood-face.html`](lab/mood-face.html) | Early face playground; uses an older u, so take shapes from `ThruBrand.swift` instead |
| [`lab/bowl.html`](lab/bowl.html) | Curvature combs for the t foot and u bowl |
| `sheets/*.png` | Construction and exploration sheets: `final.png` (wordmark construction), `system.png`, `icons.png`, `coral.png` (brand colour) |

The mockups are plain HTML: open the file in a browser, or serve the folder with
`powershell -NoProfile -ExecutionPolicy Bypass -File design/lab/serve.ps1` and open `http://localhost:8765/`.

## Sources and rebuilding

| Source | Builds |
| --- | --- |
| `source/parts/wordmark-geo.svg`, `eased-t.txt`, `u-constant.txt` | The master wordmark and its two curves; everything else derives from these |
| `source/build-app-assets.py` | Everything in `design/app/` and the `Brand` folders in both asset catalogs: `python design/source/build-app-assets.py` from the repo root |
| `source/build-brand.sh` | `design/brand/` |
| `lab/build-mockups.sh` | The mockup pages from their `*.src.html`: `bash build-mockups.sh` in `design/lab` |
| `source/build-*.sh` | The study sheets, see [`README.md`](README.md) |

Change a shape in the sources, rebuild, and the app assets, the Swift reference and the mockups stay in step. Do not
edit generated files by hand.

## Not yet updated

- `docs/brand/logo/` and the README visuals in `docs/` still show the old Instrument Sans wordmark and glass heart
  icon. They are regenerated in the last step of the redesign.
