"""Builds every app-ready design part from the wordmark master and the mockups.

Run from the repo root:  python design/source/build-app-assets.py

Writes
  design/app/icons/       tab bar icons (24 x 24) and Info badges (14 x 14), SVG, single colour
  design/app/faces/       the six mood faces (105 x 120 face box), SVG, single colour
  design/app/mood-face-points.json   smile and flat mouth outlines, resampled to the same points for morphing
  design/app/tokens.json  colours, grid, radii, type and motion from design/DESIGN-SYSTEM.md
  design/app/swift/ThruBrand.swift   reference SwiftUI: tokens, MoodFaceShape, MoodFaceTile
  HealthDashboard/Assets.xcassets/Brand/   tab icons, badges, faces and the wordmark as vector image sets
  HealthWatch/Assets.xcassets/Brand/       the faces
"""
import json, math, os, re, shutil

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
D = lambda *p: os.path.join(ROOT, *p)
PARTS = D("design", "source", "parts")
OUT = D("design", "app")
INK = "#2B1F1A"

def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)

# ---------------------------------------------------------------- geometry
bowl = open(os.path.join(PARTS, "u-constant.txt"), encoding="utf-8").read().strip()
nums = [float(n) for n in re.findall(r"-?\d+(?:\.\d+)?", bowl)]
raw = [(nums[i] - 300, nums[i + 1] - 60) for i in range(0, len(nums), 2)]  # face box coordinates

def find(x, y):
    return next(i for i, p in enumerate(raw) if abs(p[0] - x) < .01 and abs(p[1] - y) < .01)

def resample(pts, m):
    lens = [0.0]
    for a, b in zip(pts, pts[1:]):
        lens.append(lens[-1] + math.dist(a, b))
    total, out, j = lens[-1], [], 1
    for k in range(m):
        s = total * k / (m - 1)
        while j < len(lens) - 1 and lens[j] < s:
            j += 1
        a, b = pts[j - 1], pts[j]
        t = (s - lens[j - 1]) / ((lens[j] - lens[j - 1]) or 1)
        out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out

N = [6, 90, 6, 140]
i1, i2, i3 = find(30, 60), find(75, 60), find(105, 60)
smile_parts = [raw[:i1 + 1], raw[i1:i2 + 1], raw[i2:i3 + 1], raw[i3:] + [raw[0]]]
flat_parts = [[(0, 75), (30, 75)], [(30, 75), (75, 75)], [(75, 75), (105, 75)], [(105, 75), (105, 105), (0, 105), (0, 75)]]
build = lambda parts: [p for part, n in zip(parts, N) for p in resample(part, n)]
SMILE, FLAT = build(smile_parts), build(flat_parts)
r3 = lambda pts: [[round(x, 3), round(y, 3)] for x, y in pts]

write(os.path.join(OUT, "mood-face-points.json"), json.dumps({
    "about": "Mood face mouth outlines in the face box (105 x 120, origin top left, y down). Both lists have the same number "
             "of points in the same order, so the mouth morphs by interpolating point by point. The frown is the smile "
             "with y replaced by 180 - y, and the flat bar mirrors onto itself. mood -1 frown, 0 flat, 1 smile: for "
             "mood >= 0 lerp(flat, smile, mood), else lerp(flat, frown, -mood). Eyes: 30 x 30 squares at x 0 and x 75, y 0.",
    "faceBox": [105, 120], "mouthBand": [60, 120],
    "smile": r3(SMILE), "flat": r3(FLAT)}, separators=(",", ":")) + "\n")

# ---------------------------------------------------------------- faces
EYES = {
    "open": '<rect x="0" y="0" width="30" height="30"/><rect x="75" y="0" width="30" height="30"/>',
    "asleep": '<rect x="0" y="15" width="30" height="15"/><rect x="75" y="15" width="30" height="15"/>',
    "wink": '<rect x="0" y="15" width="30" height="15"/><rect x="75" y="0" width="30" height="30"/>',
    "record": '<path d="M0 30A15 15 0 0 1 30 30Z"/><path d="M75 30A15 15 0 0 1 105 30Z"/>',
}
SMILE_D = "M" + " ".join("%g %g" % (round(x, 3), round(y, 3)) for x, y in raw) + "Z"
MOUTH = {
    "smile": '<path d="%s"/>' % SMILE_D,
    "flat": '<rect x="0" y="75" width="105" height="30"/>',
    "frown": '<path transform="matrix(1 0 0 -1 0 180)" d="%s"/>' % SMILE_D,
}
FACES = {  # asset name: (file, eyes, mouth, use)
    "FaceSmile": ("face-smile", "open", "smile", "Push, and the default face"),
    "FaceFlat": ("face-flat", "open", "flat", "Moderate"),
    "FaceFrown": ("face-frown", "open", "frown", "Recover"),
    "FaceAsleep": ("face-asleep", "asleep", "smile", "Sleep screen, bedtime, alarm"),
    "FaceWink": ("face-wink", "wink", "smile", "Saved: food logged, data synced"),
    "FaceRecord": ("face-record", "record", "smile", "New record or streak"),
}
def face_svg(eyes, mouth):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="105" height="120" viewBox="0 0 105 120">'
            '<g fill="%s">%s%s</g></svg>\n' % (INK, EYES[eyes], MOUTH[mouth]))
for name, (fn, e, m, _) in FACES.items():
    write(os.path.join(OUT, "faces", fn + ".svg"), face_svg(e, m))

# ---------------------------------------------------------------- icons
TABS = {  # asset name: (file, label, svg body), 24 x 24, as drawn in the mockups
    "TabToday": ("tab-today", "Today", '<rect x="3" y="3" width="6" height="6"/><rect x="15" y="3" width="6" height="6"/><path d="M3 15h6c0 1.7 1.3 3 3 3s3-1.3 3-3h6c0 5-4 9-9 9s-9-4-9-9z"/>'),
    "TabTrends": ("tab-trends", "Trends", '<rect x="3" y="12" width="5" height="9"/><rect x="9.5" y="7" width="5" height="14"/><rect x="16" y="3" width="5" height="18"/>'),
    "TabWorkouts": ("tab-workouts", "Workouts", '<rect x="2" y="7" width="4" height="10"/><rect x="18" y="7" width="4" height="10"/><rect x="6" y="10" width="12" height="4"/>'),
    "TabNutrition": ("tab-nutrition", "Nutrition", '<path d="M2 9h20c0 6-4.5 11-10 11S2 15 2 9z"/><rect x="11" y="2" width="2" height="6"/>'),
    "TabInfo": ("tab-info", "Info", '<path d="M12 2a10 10 0 1 1 0 20 10 10 0 0 1 0-20zm-1.5 8v8h3v-8zm0-4v3h3V6z"/>'),
}
BADGES = {  # asset name: (file, use, svg body), 14 x 14, white on the area colour square in Info
    "BadgeJournal": ("badge-journal", "Journal", '<rect x="2" y="2" width="10" height="10"/>'),
    "BadgeGoals": ("badge-goals", "Goals", '<rect x="3" y="2" width="2" height="10"/><rect x="5" y="2" width="6" height="5"/>'),
    "BadgeAir": ("badge-air", "Bedroom", '<rect x="2" y="3" width="10" height="2"/><rect x="2" y="7" width="7" height="2"/><rect x="2" y="11" width="9" height="2"/>'),
    "BadgeScale": ("badge-scale", "Body, Weigh-ins", '<rect x="2" y="7" width="10" height="5"/><path d="M3 7a4 4 0 0 1 8 0z"/>'),
    "BadgeBed": ("badge-bed", "Nights, Sleep score", '<rect x="2" y="6" width="10" height="4"/><rect x="2" y="3" width="4" height="3"/>'),
    "BadgeHeart": ("badge-heart", "Overnight readings, Recovery", '<path d="M1 7h3l1-3 2 6 1-3h5v1H8.6L7 12 5 6 4.6 8H1z"/>'),
    "BadgeLift": ("badge-lift", "Workouts, Strain", '<rect x="1" y="4" width="2" height="6"/><rect x="11" y="4" width="2" height="6"/><rect x="3" y="6" width="8" height="2"/>'),
    "BadgeAlarm": ("badge-alarm", "Alarms, naps and desk mode", '<path d="M7 2a5 5 0 1 1 0 10A5 5 0 0 1 7 2zm-1 2v4h4V7H7V4z"/>'),
    "BadgeFood": ("badge-food", "Food, Food quality", '<path d="M2 5h10c0 3-2.2 6-5 6S2 8 2 5z"/>'),
}
def icon_svg(size, body):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">'
            '<g fill="%s">%s</g></svg>\n' % (size, size, size, size, INK, body))
for name, (fn, _, body) in TABS.items():
    write(os.path.join(OUT, "icons", fn + ".svg"), icon_svg(24, body))
for name, (fn, _, body) in BADGES.items():
    write(os.path.join(OUT, "icons", fn + ".svg"), icon_svg(14, body))

# ---------------------------------------------------------------- asset catalogs
INFO = {"info": {"author": "xcode", "version": 1}}
def imageset(catalog, name, svg_src, template, dark_src=None):
    folder = os.path.join(catalog, "Brand", name + ".imageset")
    if os.path.isdir(folder):
        shutil.rmtree(folder)
    os.makedirs(folder)
    images = [{"filename": name + ".svg", "idiom": "universal"}]
    shutil.copyfile(svg_src, os.path.join(folder, name + ".svg"))
    if dark_src:
        images.append({"appearances": [{"appearance": "luminosity", "value": "dark"}], "filename": name + "-dark.svg", "idiom": "universal"})
        shutil.copyfile(dark_src, os.path.join(folder, name + "-dark.svg"))
    props = {"preserves-vector-representation": True}
    if template:
        props["template-rendering-intent"] = "template"
    write(os.path.join(folder, "Contents.json"), json.dumps(dict(images=images, info=INFO["info"], properties=props), indent=2) + "\n")

phone_cat, watch_cat = D("HealthDashboard", "Assets.xcassets"), D("HealthWatch", "Assets.xcassets")
for cat in (phone_cat, watch_cat):
    write(os.path.join(cat, "Brand", "Contents.json"), json.dumps(INFO, indent=2) + "\n")
for name, (fn, _, _) in TABS.items():
    imageset(phone_cat, name, os.path.join(OUT, "icons", fn + ".svg"), True)
for name, (fn, _, _) in BADGES.items():
    imageset(phone_cat, name, os.path.join(OUT, "icons", fn + ".svg"), True)
for name, (fn, _, _, _) in FACES.items():
    for cat in (phone_cat, watch_cat):
        imageset(cat, name, os.path.join(OUT, "faces", fn + ".svg"), True)
brand = D("design", "brand")
imageset(phone_cat, "Wordmark", os.path.join(brand, "thru-wordmark-salmon.svg"), False, os.path.join(brand, "thru-wordmark-salmon-on-dark.svg"))
imageset(phone_cat, "WordmarkMono", os.path.join(brand, "thru-wordmark-ink.svg"), True)

# ---------------------------------------------------------------- tokens
def rgb(h):
    return [round(int(h[i:i + 2], 16) / 255, 3) for i in (1, 3, 5)]
COLOURS = {
    "paper": ("#F9F6ED", "Page background, the face on the icon"),
    "card": ("#FFFDF8", "Card surface, solid, with a 1 pt hairline of ink at 8%"),
    "ink": ("#2B1F1A", "All text and the wordmark; secondary text is ink at 60%"),
    "accent": ("#F07B62", "Salmon brand colour: the u, the icon tile, one prominent button per screen, links"),
    "darkSurface": ("#1C1714", "Dark icon, dark mode surfaces"),
    "glowRed": ("#E02E3D", "Background glow only, 14 to 18% opacity"),
    "glowOrange": ("#F78033", "Background glow only, 14 to 18% opacity"),
    "glowAmber": ("#FCC254", "Background glow only, 14 to 18% opacity"),
    "push": ("#33B378", "Recovery push zone, Push face"),
    "moderate": ("#EDAB2E", "Moderate zone, Moderate face"),
    "recover": ("#DB454C", "Recover zone, Recover face, over-limit dots"),
    "sleep": ("#9470F2", "Sleep score, stages, Asleep face"),
    "strain": ("#2978F2", "Day strain, workouts, New record face"),
    "heart": ("#21A8BD", "HRV, resting HR, breathing"),
    "body": ("#F29433", "Weight and body composition"),
    "nutrition": ("#E3598F", "Food, intake, quality"),
    "air": ("#6BBDDB", "Bedroom air and light"),
}
tokens = {
    "about": "Design tokens for the thru redesign. Source of truth: design/DESIGN-SYSTEM.md. Units are points.",
    "colours": {k: {"hex": v[0], "rgb": rgb(v[0]), "use": v[1]} for k, v in COLOURS.items()},
    "opacity": {"secondaryText": 0.6, "track": 0.10, "hairline": 0.08, "chartGrid": 0.08, "chartHistory": 0.35, "glow": [0.14, 0.18]},
    "grid": {"cell": 24, "half": 12, "quarter": 6, "double": 48},
    "radius": {"card": 24, "prominentButton": 24, "chip": 12, "tileFraction": 0.225, "other": "full circles only"},
    "bar": {"thickness": 12, "ends": "square", "targetTick": 2, "ringThickness": 12, "ringEnds": "round"},
    "type": {
        "score": {"size": 48, "line": 48, "weight": "semibold", "tabular": True},
        "title": {"size": 28, "line": 36, "weight": "semibold"},
        "heading": {"size": 17, "line": 24, "weight": "semibold"},
        "value": {"size": 22, "line": 24, "weight": "semibold", "tabular": True},
        "body": {"size": 17, "line": 24, "weight": "regular"},
        "label": {"size": 13, "line": 18, "weight": "regular", "opacity": 0.6},
    },
    "motion": {"mouthMorph": 0.6, "glowFade": 0.8, "blinkEvery": [3, 5], "blink": 0.24, "wink": 0.9, "curve": "easeInOut", "reduceMotion": "switch instantly"},
    "moodFace": {"faceHeightInTile": 0.56, "push": "mood 1", "moderate": "mood 0", "recover": "mood -1", "fromRecovery": "clamp((score - 50) / 17, -1, 1)"},
}
write(os.path.join(OUT, "tokens.json"), json.dumps(tokens, indent=2) + "\n")

# ---------------------------------------------------------------- Swift reference
def swift_list(pts):
    flat = [v for p in pts for v in (round(p[0], 3), round(p[1], 3))]
    lines = []
    for i in range(0, len(flat), 12):
        lines.append("        " + ", ".join("%g" % v for v in flat[i:i + 12]) + ",")
    return "\n".join(lines)

def colour(h):
    r, g, b = rgb(h)
    return "Color(red: %s, green: %s, blue: %s)" % (r, g, b)

swift = '''// Reference SwiftUI for the thru redesign. Generated by design/source/build-app-assets.py; do not edit by hand.
// Not part of any target yet: move it into Shared/ (so the app, watch and widgets can all use it) when the redesign starts.
// Written without a compiler on hand: build it once in Xcode before relying on it.

import SwiftUI

/// Design tokens from design/DESIGN-SYSTEM.md.
enum ThruBrand {
    enum Colors {
%(colours)s
    }

    enum Grid {
        static let cell: CGFloat = 24
        static let half: CGFloat = 12
        static let quarter: CGFloat = 6
        static let double: CGFloat = 48
    }

    enum Radius {
        static let card: CGFloat = 24
        static let prominentButton: CGFloat = 24
        static let chip: CGFloat = 12
        /// Mood face tile and app icon corner, as a fraction of the tile side.
        static let tileFraction: CGFloat = 0.225
    }

    enum Bar {
        static let thickness: CGFloat = 12
        static let targetTick: CGFloat = 2
    }

    /// The mood for a recovery score: 1 smile (push, 67 and up), 0 flat, -1 frown (recover, below 34).
    static func mood(recovery: Double) -> Double {
        max(-1, min(1, (recovery - 50) / 17))
    }
}

enum MoodFaceEyes {
    case open, asleep, wink, record
}

/// The mood face from the wordmark's u, in a 105 x 120 box, fitted into the rect.
/// mood: -1 frown, 0 flat, 1 smile; animates smoothly. lid: 0 open, 1 closed, for the blink.
struct MoodFaceShape: Shape {
    var mood: Double
    var lid: Double = 0
    var eyes: MoodFaceEyes = .open

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(mood, lid) }
        set { mood = newValue.first; lid = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width / 105, rect.height / 120)
        let ox = rect.midX - 52.5 * s
        let oy = rect.midY - 60 * s
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
            CGRect(x: ox + x * s, y: oy + y * s, width: w * s, height: h * s)
        }

        var p = Path()
        let closed = min(max(lid, 0), 1) * 0.9
        switch eyes {
        case .open:
            p.addRect(box(0, 30 * closed, 30, 30 * (1 - closed)))
            p.addRect(box(75, 30 * closed, 30, 30 * (1 - closed)))
        case .asleep:
            p.addRect(box(0, 15, 30, 15))
            p.addRect(box(75, 15, 30, 15))
        case .wink:
            p.addRect(box(0, 15, 30, 15))
            p.addRect(box(75, 0, 30, 30))
        case .record:
            for cx in [15.0, 90.0] {
                p.move(to: pt(cx - 15, 30))
                for i in 1...24 {
                    let a = Double.pi * (1 - Double(i) / 24)
                    p.addLine(to: pt(cx + 15 * cos(a), 30 - 15 * sin(a)))
                }
                p.closeSubpath()
            }
        }

        let m = min(max(mood, -1), 1)
        let e = abs(m)
        let a = MoodFacePoints.flat
        let b = m >= 0 ? MoodFacePoints.smile : MoodFacePoints.frown
        var i = 0
        while i < a.count {
            let x = a[i] + (b[i] - a[i]) * e
            let y = a[i + 1] + (b[i + 1] - a[i + 1]) * e
            if i == 0 { p.move(to: pt(x, y)) } else { p.addLine(to: pt(x, y)) }
            i += 2
        }
        p.closeSubpath()
        return p
    }
}

/// The face on its tile: paper face on a zone or area colour, corner 22.5%%, face 56%% of the tile height.
/// Animate with .animation(.easeInOut(duration: 0.6), value: mood).
struct MoodFaceTile: View {
    var mood: Double
    var color: Color
    var eyes: MoodFaceEyes = .open
    var lid: Double = 0
    var faceColor: Color = ThruBrand.Colors.paper

    var body: some View {
        GeometryReader { g in
            let side = min(g.size.width, g.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: side * ThruBrand.Radius.tileFraction, style: .continuous)
                    .fill(color)
                MoodFaceShape(mood: mood, lid: lid, eyes: eyes)
                    .fill(faceColor)
                    .frame(width: side * 0.56 * 105 / 120, height: side * 0.56)
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Mouth outlines in the face box, x and y interleaved; both lists match point for point (see mood-face-points.json).
enum MoodFacePoints {
    static let smile: [Double] = [
%(smile)s
    ]
    static let flat: [Double] = [
%(flat)s
    ]
    /// The smile turned over inside the mouth band (y becomes 180 - y).
    static let frown: [Double] = smile.enumerated().map { $0.offset %% 2 == 1 ? 180 - $0.element : $0.element }
}
''' % {
    "colours": "\n".join("        /// %s\n        static let %s = %s" % (v[1], k, colour(v[0])) for k, v in COLOURS.items()),
    "smile": swift_list(SMILE), "flat": swift_list(FLAT),
}
write(os.path.join(OUT, "swift", "ThruBrand.swift"), swift)

print("faces", len(FACES), "tabs", len(TABS), "badges", len(BADGES), "mouth points", len(SMILE))
