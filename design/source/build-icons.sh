#!/usr/bin/env bash
# Builds icons.src.svg: app icon options built from the mood face (the final u), each shown as the
# iOS light, dark and tinted icon, at 60 and 29 px, and on a home screen row next to the current icon.
set -e
. ./lib.sh
BG="#F9F6ED"; INK="#2B1F1A"
UB=$(cat parts/u-constant.txt)
EYES='<path d="M300 60 H330 V90 H300 Z M375 60 H405 V90 H375 Z"/>'
FACE="$EYES<path d=\"$UB\"/>"
GLOW='<defs><radialGradient id="gl1" cx="0.15" cy="0.1" r="0.9"><stop offset="0" stop-color="#E02E3D"/><stop offset="0.55" stop-color="#F78033"/><stop offset="1" stop-color="#FCC254"/></radialGradient></defs>'
# icon x y size tile ink [extra-defs]
icon() {
  local s=$3 k ox oy r
  k=$(awk -v s=$s 'BEGIN{print s*0.56/120}')
  ox=$(awk -v x=$1 -v s=$s -v k=$k 'BEGIN{print x+(s-105*k)/2-300*k}')
  oy=$(awk -v y=$2 -v s=$s -v k=$k 'BEGIN{print y+(s-120*k)/2-60*k}')
  r=$(awk -v s=$s 'BEGIN{print s*0.225}')
  echo "<rect x=\"$1\" y=\"$2\" width=\"$s\" height=\"$s\" rx=\"$r\" fill=\"$4\" stroke=\"#2B1F1A\" stroke-opacity=\"0.12\" stroke-width=\"1\"/>"
  echo "<g transform=\"translate($ox $oy) scale($k)\" fill=\"$5\">$FACE</g>"
}
ROWS=("A|Ink and paper|#2B1F1A|#F9F6ED|#141010|#F9F6ED|Bauhaus, calm; never mistaken for a recovery state"
      "B|Coral|#E8543D|#F9F6ED|#2A1512|#E8543D|Warmest, continues the glass heart; close to the Recover red"
      "C|Paper and ink|#F9F6ED|#2B1F1A|#1C1714|#F9F6ED|Lightest; can look like a blank tile on light wallpapers"
      "D|Glow gradient|url(#gl1)|#FFFFFF|#1C1714|url(#gl1)|The current icon's colours behind the face; warm, but busy at small sizes"
      "E|Paper and coral|#F9F6ED|#E8543D|#1C1714|#E8543D|Coral face on paper; light but recognisable")
{
echo "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" width=\"1400\" height=\"1330\" viewBox=\"0 0 1400 1330\" font-family=\"Inter\">"
echo "$GLOW"
echo "<rect width=\"1400\" height=\"1330\" fill=\"$BG\"/>"
echo "<text x=\"40\" y=\"60\" font-size=\"28\" font-weight=\"600\" fill=\"$INK\">App icon options</text>"
echo "<text x=\"40\" y=\"88\" font-size=\"15\" fill=\"#7A6A5C\">The mood face as the icon. Each row: light icon, dark icon, tinted icon, then 60 and 29 px, then on a home screen with the current icon.</text>"
for c in "300|Light" "500|Dark" "700|Tinted" "880|60 / 29 px" "1060|Home screen"; do echo "<text x=\"${c%%|*}\" y=\"128\" font-size=\"13\" fill=\"#7A6A5C\">${c#*|}</text>"; done
y=145
for r in "${ROWS[@]}"; do
  IFS="|" read -r id name tile ink dtile dink note <<<"$r"
  echo "<text x=\"40\" y=\"$((y+40))\" font-size=\"20\" font-weight=\"600\" fill=\"$INK\">$id  $name</text>"
  echo "<foreignObject/>"
  echo "<text x=\"40\" y=\"$((y+64))\" font-size=\"13\" fill=\"#7A6A5C\">$(echo "$note" | cut -d';' -f1);</text>"
  echo "<text x=\"40\" y=\"$((y+82))\" font-size=\"13\" fill=\"#7A6A5C\">$(echo "$note" | cut -d';' -f2- | sed 's/^ //')</text>"
  icon 300 $y 170 "$tile" "$ink"
  echo "<rect x=\"485\" y=\"$((y-8))\" width=\"186\" height=\"186\" rx=\"22\" fill=\"#0D0B0A\"/>"
  icon 493 $y 170 "$dtile" "$dink"
  echo "<rect x=\"685\" y=\"$((y-8))\" width=\"186\" height=\"186\" rx=\"22\" fill=\"#0D0B0A\"/>"
  icon 693 $y 170 "#2A2A2A" "#D9D9D9"
  icon 885 $((y+20)) 60 "$tile" "$ink"; icon 960 $((y+35)) 29 "$tile" "$ink"
  echo "<rect x=\"1040\" y=\"$((y-8))\" width=\"320\" height=\"186\" rx=\"22\" fill=\"#C9B9A4\"/>"
  icon 1065 $((y+45)) 76 "$tile" "$ink"
  echo "<clipPath id=\"cur$id\"><rect x=\"1162\" y=\"$((y+45))\" width=\"76\" height=\"76\" rx=\"17.1\"/></clipPath><image clip-path=\"url(#cur$id)\" x=\"1162\" y=\"$((y+45))\" width=\"76\" height=\"76\" xlink:href=\"$A/AppIcon.png\" href=\"$A/AppIcon.png\"/>"
  echo "<rect x=\"1259\" y=\"$((y+45))\" width=\"76\" height=\"76\" rx=\"17.1\" fill=\"#3B7DD8\"/><circle cx=\"1297\" cy=\"$((y+83))\" r=\"18\" fill=\"none\" stroke=\"#FFFFFF\" stroke-width=\"6\"/>"
  echo "<text x=\"1103\" y=\"$((y+140))\" font-size=\"12\" fill=\"#2B1F1A\" text-anchor=\"middle\">thru</text><text x=\"1200\" y=\"$((y+140))\" font-size=\"12\" fill=\"#2B1F1A\" text-anchor=\"middle\">now</text><text x=\"1297\" y=\"$((y+140))\" font-size=\"12\" fill=\"#2B1F1A\" text-anchor=\"middle\">other app</text>"
  y=$((y+232))
done
echo "</svg>"
} > icons.src.svg
sed -i '/<foreignObject\/>/d' icons.src.svg
echo built
