"""Draws the app icon: three concentric rings in the app's palette on a dark background.
Usage: python3 scripts/make-icon.py HealthDashboard/Assets.xcassets/AppIcon.appiconset/AppIcon.png (needs Pillow)."""
import math, sys
from PIL import Image, ImageDraw

out = sys.argv[1]
S = 4096                      # draw at 4x, downscale for smooth edges
img = Image.new("RGB", (S, S))
px = img.load()
# Vertical gradient background, near black to a deep blue-grey
top, bottom = (14, 16, 24), (30, 34, 52)
for y in range(S):
    f = y / (S - 1)
    c = tuple(int(top[i] + (bottom[i] - top[i]) * f) for i in range(3))
    for x in range(S):
        px[x, y] = c
d = ImageDraw.Draw(img)

def rgb(r, g, b): return (int(r * 255), int(g * 255), int(b * 255))
rings = [  # (colour, fill fraction) outer to inner: recovery, sleep, strain
    (rgb(0.20, 0.70, 0.47), 0.78),
    (rgb(0.58, 0.44, 0.95), 0.66),
    (rgb(0.16, 0.47, 0.95), 0.52),
]
cx = cy = S / 2
width = S * 0.085
gap = S * 0.025
radius = S * 0.36
for colour, frac in rings:
    box = [cx - radius, cy - radius, cx + radius, cy + radius]
    track = tuple(int(c * 0.28 + top[i] * 0.72) for i, c in enumerate(colour))
    d.ellipse(box, outline=track, width=int(width))
    start, end = -90, -90 + 360 * frac
    d.arc(box, start=start, end=end, fill=colour, width=int(width))
    # Round caps at both ends of the arc
    r_mid = radius - width / 2
    for a in (start, end):
        t = math.radians(a)
        x, y = cx + r_mid * math.cos(t), cy + r_mid * math.sin(t)
        d.ellipse([x - width / 2, y - width / 2, x + width / 2, y + width / 2], fill=colour)
    radius -= width + gap

img.resize((1024, 1024), Image.LANCZOS).save(out, "PNG")
print("wrote", out)
