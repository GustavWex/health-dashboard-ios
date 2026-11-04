#!/usr/bin/env bash
# Builds lockups.src.svg (1600 x 640): the icon + wordmark lockup at five sizes. Run from docs/source.
# Rule: the icon sets the size; the wordmark is set at 0.86 x the icon height with a gap of 0.25 x the icon.
# Below 40 px the cut would be under 2 px, so the small lockup uses the solid wordmark; the smallest is the icon alone.
set -e
. ./lib.sh

CY=330   # shared centre line

icon() { # id x size
  local y; y=$(awk -v c=$CY -v s=$3 'BEGIN{printf "%.2f", c - s/2}')
  local r; r=$(awk -v s=$3 'BEGIN{printf "%.2f", s*0.225}')
  echo "  <clipPath id=\"clip-$1\"><rect x=\"$2\" y=\"$y\" width=\"$3\" height=\"$3\" rx=\"$r\"/></clipPath>" >> /tmp/lockup-defs.$$
  echo "  <image clip-path=\"url(#clip-$1)\" x=\"$2\" y=\"$y\" width=\"$3\" height=\"$3\" xlink:href=\"$A/AppIcon.png\" href=\"$A/AppIcon.png\"/>"
}
lockword() { # x icon-size cut(1|0)
  local f; f=$(awk -v s=$2 'BEGIN{printf "%.2f", s*0.86}')
  local gap; gap=$(awk -v s=$2 'BEGIN{printf "%.2f", s*0.25}')
  local x; x=$(awk -v a=$1 -v s=$2 -v g=$gap 'BEGIN{printf "%.2f", a+s+g}')
  local base; base=$(awk -v c=$CY -v f=$f 'BEGIN{printf "%.2f", c + 0.72*f/2}')
  if [ "$3" = 1 ]; then wordmark "$x" "$base" "$f"
  else wordmark_solid "$x" "$base" "$f"; fi
}
cap() { echo "  <text x=\"$1\" y=\"500\" font-size=\"17\" font-weight=\"600\" fill=\"#2B1F1A\">$2</text><text x=\"$1\" y=\"524\" font-size=\"15\" fill=\"#7A6A5C\">$3</text>"; }

: > /tmp/lockup-defs.$$
BODY=$(
  icon xl 130 160; lockword 130 160 1
  icon l 667 96;   lockword 667 96 1
  icon m 1025 56;  lockword 1025 56 1
  icon s 1271 32;  lockword 1271 32 0
  icon xs 1450 20
)
DEFS=$(cat /tmp/lockup-defs.$$); rm -f /tmp/lockup-defs.$$

cat > lockups.src.svg <<EOF
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1600" height="640" viewBox="0 0 1600 640" font-family="Inter">
  <defs>
$(paper_defs 1600 640)
$DEFS
  </defs>
$(paper 1600 640 "1400 0 640" "900 380 700" "100 680 560")
  <text x="80" y="76" font-size="34" font-weight="600" fill="#2B1F1A">Logo at five sizes</text>
$(card stage 80 110 1440 450 22)
  <path d="M110 $CY H1490" stroke="#E6DDCD" stroke-width="1" stroke-dasharray="4 6"/>
$BODY
$(cap 130 "1  Full" "Icon 160 px, README header")
$(cap 667 "2  Large" "Icon 96 px, slides")
$(cap 1025 "3  Medium" "Icon 56 px, nav")
$(cap 1271 "4  Small" "32 px, no cut")
$(cap 1430 "5  Icon" "20 px")
</svg>
EOF
echo built lockups.src.svg
