#!/usr/bin/env bash
# Builds colours.src.svg: brand colour candidates. Each row: the app icon (paper face on the colour),
# the dark icon (colour face on dark), the icon at 60 and 29 px, and the wordmark with the u in that colour,
# on paper and on dark. The note says how close the colour sits to a colour the app already uses for meaning.
set -e
BG="#F9F6ED"; INK="#2B1F1A"
FROZEN_NOU='M22.5 30 H52.5 V60 H22.5 Z M0 60 H75 V90 H0 Z M90 0 H120 V90 H90 Z M90 120 H120 V180 H90 Z M165 120 H195 V180 H165 Z M120.758 90 A37.5 37.5 0 0 1 194.242 90 Z M210 60 H240 V90 H210 Z M240 90 A30 30 0 0 1 270 60 V90 Z M270 60 H285 V90 H270 Z M210 120 H240 V180 H210 Z'
TE=$(cat parts/eased-t.txt); UB=$(cat parts/u-constant.txt)
NOU="$FROZEN_NOU $TE"
UPATH="M300 60 H330 V90 H300 Z M375 60 H405 V90 H375 Z $UB"
icon() { # x y size tile ink
  local s=$3 k ox oy r
  k=$(awk -v s=$s 'BEGIN{print s*0.56/120}')
  ox=$(awk -v x=$1 -v s=$s -v k=$k 'BEGIN{print x+(s-105*k)/2-300*k}')
  oy=$(awk -v y=$2 -v s=$s -v k=$k 'BEGIN{print y+(s-120*k)/2-60*k}')
  r=$(awk -v s=$s 'BEGIN{print s*0.225}')
  echo "<rect x=\"$1\" y=\"$2\" width=\"$s\" height=\"$s\" rx=\"$r\" fill=\"$4\"/>"
  echo "<g transform=\"translate($ox $oy) scale($k)\" fill=\"$5\"><path d=\"$UPATH\"/></g>"
}
word() { # x y height ink ucolour
  local k; k=$(awk -v h=$3 'BEGIN{print h/180}')
  echo "<g transform=\"translate($1 $2) scale($k)\"><path fill=\"$4\" d=\"$NOU\"/><path fill=\"$5\" d=\"$UPATH\"/></g>"
}
ROWS=("Coral|#E8543D|Today's accent. Close to the Recover red"
      "Terracotta|#C4522F|Earthy clay red. Browner than the Recover red"
      "Persimmon|#F26522|Bright orange-red. Close to the Body orange"
      "Cobalt|#2A3FD1|Bauhaus blue. Deeper than the Strain blue"
      "Oxblood|#8E2B2F|Deep red-brown. Fades on dark backgrounds"
      "Bottle green|#1F5B47|Deep green. Still reads as the Push green"
      "Mustard|#D9A21B|Bauhaus yellow, ink face. Close to the Moderate amber")
H=$((150 + ${#ROWS[@]}*170))
{
echo "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1400\" height=\"$H\" viewBox=\"0 0 1400 $H\" font-family=\"Inter\">"
echo "<rect width=\"1400\" height=\"$H\" fill=\"$BG\"/>"
echo "<text x=\"40\" y=\"60\" font-size=\"28\" font-weight=\"600\" fill=\"$INK\">Brand colour: icon and u</text>"
echo "<text x=\"40\" y=\"88\" font-size=\"15\" fill=\"#7A6A5C\">Each colour as the app icon, the dark icon, small sizes, and as the u in the wordmark on paper and on dark.</text>"
for c in "300|Icon" "450|Dark" "590|60 / 29 px" "730|Wordmark on paper" "1080|On dark"; do echo "<text x=\"${c%%|*}\" y=\"130\" font-size=\"13\" fill=\"#7A6A5C\">${c#*|}</text>"; done
y=150
for r in "${ROWS[@]}"; do
  IFS="|" read -r name col note <<<"$r"
  face="#F9F6ED"; [ "$name" = "Mustard" ] && face="$INK"
  echo "<text x=\"40\" y=\"$((y+40))\" font-size=\"20\" font-weight=\"600\" fill=\"$INK\">$name</text>"
  echo "<text x=\"40\" y=\"$((y+62))\" font-size=\"13\" fill=\"#7A6A5C\">$col</text>"
  echo "<foreignObject/>"
  n1=$(echo "$note" | cut -d'.' -f1); n2=$(echo "$note" | cut -d'.' -f2- | sed 's/^ //')
  echo "<text x=\"40\" y=\"$((y+86))\" font-size=\"12\" fill=\"#7A6A5C\">$n1.</text><text x=\"40\" y=\"$((y+103))\" font-size=\"12\" fill=\"#7A6A5C\">$n2</text>"
  icon 300 $y 130 "$col" "$face"
  echo "<rect x=\"440\" y=\"$((y-6))\" width=\"142\" height=\"142\" rx=\"20\" fill=\"#0D0B0A\"/>"
  icon 446 $y 130 "#1C1714" "$col"
  icon 600 $((y+20)) 60 "$col" "$face"; icon 672 $((y+35)) 29 "$col" "$face"
  word 730 $((y+18)) 92 "$INK" "$col"
  echo "<rect x=\"1060\" y=\"$((y-6))\" width=\"300\" height=\"142\" rx=\"20\" fill=\"#0D1117\"/>"
  word 1085 $((y+28)) 76 "#F9F6ED" "$col"
  y=$((y+170))
done
echo "</svg>"
} > colours.src.svg
sed -i '/<foreignObject\/>/d' colours.src.svg
echo built
