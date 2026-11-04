#!/usr/bin/env bash
# Builds hero.src.svg (1600 x 800). Run from docs/source.
set -e
. ./lib.sh

cat > hero.src.svg <<EOF
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1600" height="800" viewBox="0 0 1600 800" font-family="Inter">
  <defs>
$(paper_defs 1600 800)
  </defs>
$(paper 1600 800 "1320 0 720" "1080 470 820" "60 900 640")

  <g clip-path="url(#frame)">
    <image x="700" y="150" width="300" height="558" transform="rotate(-6 850 429)" xlink:href="$A/today-split.png" href="$A/today-split.png"/>
    <image x="1130" y="150" width="300" height="558" transform="rotate(6 1280 429)" xlink:href="$A/trends.png" href="$A/trends.png"/>
    <image x="886" y="70" width="360" height="670" xlink:href="$A/today.png" href="$A/today.png"/>
  </g>

  <image id="app-icon" x="80" y="110" width="207" height="207" xlink:href="$A/AppIcon.png" href="$A/AppIcon.png"/>
  <text x="108" y="400" font-size="104" font-weight="600" letter-spacing="-3" fill="#2B1F1A">thru</text>
  <text transform="translate(112 470) skewX(-12)" font-size="36" font-weight="600" fill="#E8543D">Intelligent</text>
  <text x="300" y="470" font-size="36" font-weight="500" fill="#2B1F1A">recovery, sleep and</text>
  <text x="110" y="516" font-size="36" font-weight="500" fill="#2B1F1A">strain you can see</text>
  <text x="110" y="562" font-size="36" font-weight="500" fill="#2B1F1A">right through</text>
  <text x="110" y="624" font-size="24" fill="#7A6A5C">Every number explained.</text>
  <text x="110" y="658" font-size="24" fill="#7A6A5C">Everything on device.</text>
</svg>
EOF
echo built hero.src.svg
