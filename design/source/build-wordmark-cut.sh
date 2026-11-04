#!/usr/bin/env bash
# Builds wordmark-cut.src.svg (1600 x 1210): the cut wordmark in Instrument Sans SemiBold, developed.
# Primary, Bold (Instrument Sans Bold, same cut rule), Italic (12 degree oblique), on dark, with the icon, small sizes.
set -e
. ./lib.sh
label() { echo "  <text x=\"$1\" y=\"$2\" font-size=\"18\" font-weight=\"600\" fill=\"${4:-#7A6A5C}\">$3</text>"; }
# centred x for a cut wordmark of width 454.75 at size $2 around centre $1
cx() { awk -v c=$1 -v s=$2 -v w=${3:-454.75} 'BEGIN{printf "%.1f", c - w*s/250/2}'; }

cat > wordmark-cut.src.svg <<EOF
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1600" height="1210" viewBox="0 0 1600 1210" font-family="Inter">
  <defs>
$(paper_defs 1600 1210)
  </defs>
$(paper 1600 1210 "1400 0 760" "1000 620 820" "100 1230 680")
  <text x="80" y="76" font-size="34" font-weight="600" fill="#2B1F1A">thru wordmark, see-through cut</text>

$(card main 80 110 1440 400 22)
$(wordmark_v $(cx 800 250) 400 250 "#2B1F1A" parts/wordmark-paths.svg)
$(label 108 482 "Primary, Instrument Sans SemiBold")

$(card bold 80 540 464 300 22)
$(wordmark_v $(cx 312 120 466.25) 730 120 "#2B1F1A" parts/wordmark-paths-bold.svg)
$(label 108 812 "Bold")

$(card ital 568 540 464 300 22)
$(wordmark_v $(cx 800 120 493) 730 120 "#2B1F1A" parts/wordmark-paths.svg "skewX(-12)")
$(label 596 812 "Italic")

  <rect x="1056" y="540" width="464" height="300" rx="22" fill="#0D1117"/>
$(wordmark_v $(cx 1288 120) 730 120 "#F9F6ED" parts/wordmark-paths.svg)
$(label 1084 812 "On GitHub dark" "#8B949E")

$(card lockup 80 870 708 300 22)
  <image x="150" y="955" width="130" height="130" xlink:href="$A/AppIcon.png" href="$A/AppIcon.png"/>
$(wordmark_v 300 1060 112 "#2B1F1A" parts/wordmark-paths.svg)
$(label 108 1142 "With the icon")

$(card sizes 812 870 708 300 22)
$(wordmark_v 850 1010 64 "#2B1F1A" parts/wordmark-paths.svg)
$(wordmark_solid 1110 1010 32)
$(wordmark_solid 1250 1010 16)
  <g font-size="15" fill="#7A6A5C">
    <text x="850" y="1050">64 px, cut</text>
    <text x="1110" y="1050">32 px, solid</text>
    <text x="1250" y="1050">16 px, solid</text>
  </g>
$(label 840 1142 "Small sizes")
</svg>
EOF
echo built wordmark-cut.src.svg
