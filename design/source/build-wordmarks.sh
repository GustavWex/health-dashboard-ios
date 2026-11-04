#!/usr/bin/env bash
# Builds wordmarks.src.svg (1600 x 940): five directions for the "thru" wordmark. Run from docs/source.
set -e
. ./lib.sh

label() { echo "  <text x=\"$1\" y=\"$2\" font-size=\"18\" font-weight=\"600\" fill=\"#7A6A5C\">$3</text>"; }

# Monoline letters on a baseline at y=0, x-height 90, ascender 140.
MONO='<path d="M20 -130 V-24 Q20 0 44 0 H54 M0 -90 H54"/>
      <path d="M86 -140 V0 M86 -54 Q86 -90 121 -90 Q156 -90 156 -54 V0"/>
      <path d="M190 -90 V0 M190 -48 Q190 -90 232 -90 H240"/>
      <path d="M270 -90 V-36 Q270 0 305 0 Q340 0 340 -36 V-90 M340 -90 V0"/>'

cat > wordmarks.src.svg <<EOF
<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="940" viewBox="0 0 1600 940" font-family="Inter">
  <defs>
$(paper_defs 1600 940)
  </defs>
$(paper 1600 940 "1400 0 700" "1000 520 760" "100 960 620")
  <text x="80" y="76" font-size="34" font-weight="600" fill="#2B1F1A">thru wordmark, five directions</text>

$(card w1 80 110 464 360 22)
$(card w2 568 110 464 360 22)
$(card w3 1056 110 464 360 22)
$(card w4 80 510 708 360 22)
$(card w5 812 510 708 360 22)

  <!-- 1 Soft monoline: drawn with round strokes, like SF Rounded -->
  <g transform="translate(142 352)" fill="none" stroke="#2B1F1A" stroke-width="24" stroke-linecap="round" stroke-linejoin="round">
    $MONO
  </g>
$(label 108 442 "1  Soft monoline")

  <!-- 2 Rest to strain: weight rises letter by letter (weights set in VectorCraft) -->
  <text id="ramp" x="800" y="350" font-family="Segoe UI Variable" font-size="160" text-anchor="middle" fill="#2B1F1A">thru</text>
$(label 596 442 "2  Rest to strain")

  <!-- 3 See-through: a heavy grotesk with a slit cut through it (cut in VectorCraft) -->
  <text id="cut" x="1288" y="350" font-size="170" font-weight="600" letter-spacing="-6" text-anchor="middle" fill="#2B1F1A">thru</text>
$(label 1084 442 "3  See-through cut")

  <!-- 4 Warm serif -->
  <text x="434" y="760" font-family="Constantia" font-weight="bold" font-size="190" letter-spacing="-4" text-anchor="middle" fill="#2B1F1A">thru</text>
$(label 108 842 "4  Warm serif")

  <!-- 5 One line: the whole word in a single stroke, starting from a data point -->
  <g transform="translate(990 752)" fill="none" stroke="#2B1F1A" stroke-width="16" stroke-linecap="round" stroke-linejoin="round">
    <path d="M20 -130 V-24 Q20 0 44 0 C 70 0 88 -96 88 -140 V0 V-54 Q88 -90 123 -90 Q158 -90 158 -54 V-12 Q158 0 168 0 Q182 0 182 -16 V-90 V-48 Q182 -90 222 -90 Q182 -90 182 -48 V0 C 186 8 236 6 256 -30 V-90 V-36 Q256 0 291 0 Q326 0 326 -36 V-90 V-14 Q326 0 344 0"/>
    <path d="M0 -90 H52"/>
  </g>
  <circle cx="1010" cy="622" r="11" fill="#E8543D"/>
$(label 840 842 "5  One line")
</svg>
EOF
echo built wordmarks.src.svg
