#!/usr/bin/env bash
# Builds the analysis slides: slide-<topic>-portrait.src.svg (1290 x 2796, App Store 6.9 inch)
# and slide-<topic>-wide.src.svg (1600 x 900, README). Run from docs/source.
set -e
. ./lib.sh

# topic | screenshot | area colour | headline line 1 | line 2 | chip 1 | chip 2 | chip 3 | wide left | wide right
SLIDES=(
  "sleep|sleep.png|#9470F2|See where your|sleep points went.|Sleep score out of 100|Six markers, each checked|The exact cost of every marker|sleep-week.png|sleep-month.png"
  "nutrition|nutrition.png|#E3598F|Know what your|food is doing.|Burn learned from your weight|Food quality out of 100|Protein per kg of body weight|nutrition-quality.png|nutrition-burn.png"
  "training|workouts.png|#2978F2|Train hard on|the right days.|Day strain from 0 to 21|Fitness, form and load|Your week against your usual|workouts-week.png|workouts-detail.png"
)

chip() { # x y w h size colour text
  card chip "$1" "$2" "$3" "$4" $(( $4 / 2 ))
  echo "  <circle cx=\"$(( $1 + $4 / 2 ))\" cy=\"$(( $2 + $4 / 2 ))\" r=\"$(( $5 / 3 ))\" fill=\"$6\"/>"
  echo "  <text x=\"$(( $1 + $4 / 2 + $5 ))\" y=\"$(( $2 + $4 / 2 + $5 * 36 / 100 ))\" font-size=\"$5\" font-weight=\"500\" fill=\"#2B1F1A\">$7</text>"
}

for s in "${SLIDES[@]}"; do
  IFS="|" read -r topic shot colour h1 h2 c1 c2 c3 left right <<<"$s"

  cat > "slide-$topic-portrait.src.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1290" height="2796" viewBox="0 0 1290 2796" font-family="Inter">
  <defs>
$(paper_defs 1290 2796 | sed 's/rx="28"/rx="0"/')
  </defs>
$(paper 1290 2796 "1200 200 1100" "200 1500 1200" "1100 2700 1100")
  <image x="100" y="150" width="104" height="104" xlink:href="$A/AppIcon.png" href="$A/AppIcon.png"/>
$(wordmark 218 222 52)
  <text x="100" y="420" font-size="96" font-weight="600" letter-spacing="-2" fill="#2B1F1A">$h1</text>
  <text x="100" y="530" font-size="96" font-weight="600" letter-spacing="-2" fill="#2B1F1A">$h2</text>
$(chip 100 620 600 84 34 "$colour" "$c1")
$(chip 100 720 600 84 34 "$colour" "$c2")
$(chip 100 820 600 84 34 "$colour" "$c3")
  <image x="195" y="1010" width="900" height="1674" xlink:href="$A/$shot" href="$A/$shot"/>
</svg>
EOF

  cat > "slide-$topic-wide.src.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1600" height="900" viewBox="0 0 1600 900" font-family="Inter">
  <defs>
$(paper_defs 1600 900)
  </defs>
$(paper 1600 900 "1400 0 720" "1150 520 760" "100 920 620")
  <image x="80" y="96" width="64" height="64" xlink:href="$A/AppIcon.png" href="$A/AppIcon.png"/>
$(wordmark 154 140 32)
  <text x="80" y="300" font-size="64" font-weight="600" letter-spacing="-1.5" fill="#2B1F1A">$h1</text>
  <text x="80" y="376" font-size="64" font-weight="600" letter-spacing="-1.5" fill="#2B1F1A">$h2</text>
$(chip 80 450 470 64 24 "$colour" "$c1")
$(chip 80 530 470 64 24 "$colour" "$c2")
$(chip 80 610 470 64 24 "$colour" "$c3")
  <image x="660" y="236" width="280" height="521" xlink:href="$A/$left" href="$A/$left"/>
  <image x="1290" y="236" width="280" height="521" xlink:href="$A/$right" href="$A/$right"/>
  <image x="950" y="128" width="330" height="614" xlink:href="$A/$shot" href="$A/$shot"/>
</svg>
EOF
  echo "built $topic"
done
