#!/usr/bin/env bash
# Builds u-fix.src.svg: ways to keep the u readable at small sizes, each at 96, 64, 48, 32 and 24 px.
# Flat paper background so the slit can be drawn as a paper-coloured band over the solid letters.
set -e
BG="#F9F6ED"; INK="#2B1F1A"
P=$(sed 's/fill="[^"]*"//g' parts/wordmark-paths.svg)
# Stems that cross the current slit (y 103.3 to 119.36 in the 250 px set): filling them gives the solid word.
BR='<path d="M24.5 103 H56.25 V119.7 H24.5Z M105.75 103 H137.25 V119.7 H105.75Z M195.25 103 H227 V119.7 H195.25Z M250 103 H281.5 V119.7 H250Z M335.75 103 H367.25 V119.7 H335.75Z M423 103 H454.75 V119.7 H423Z"/>'
# word x baseline size variant
word() {
  local s y; s=$(awk -v f=$3 'BEGIN{printf "%.5f", f/250}'); y=$(awk -v b=$2 -v f=$3 'BEGIN{printf "%.2f", b-180*f/250}')
  echo "<g transform=\"translate($1 $y) scale($s)\" fill=\"$INK\">"
  case $4 in
    current) echo "$P";;
    solid)   echo "$P$BR";;
    thin)    echo "$P$BR<rect x=\"-4\" y=\"106.3\" width=\"466\" height=\"10\" fill=\"$BG\"/>";;
    high)    echo "$P$BR<rect x=\"-4\" y=\"83.2\" width=\"466\" height=\"16.06\" fill=\"$BG\"/>";;
    uwhole)  echo "$P<path d=\"M335.75 103 H367.25 V119.7 H335.75Z M423 103 H454.75 V119.7 H423Z\"/>";;
    uwholethin) echo "$P$BR<rect x=\"-4\" y=\"106.3\" width=\"300\" height=\"10\" fill=\"$BG\"/>";;
  esac
  echo "</g>"
}
ROWS=("current|1  Now: cut through all four letters"
      "thin|2  Thinner cut, 0.055 x height"
      "high|3  Cut moved up, u keeps its bowl"
      "uwhole|4  Cut stops before the u"
      "uwholethin|5  Thinner cut, stops before the u"
      "solid|6  No cut")
SIZES=(96 64 48 32 24)
XS=(440 720 920 1080 1200)
{
echo "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1340\" height=\"1000\" viewBox=\"0 0 1340 1000\" font-family=\"Inter\">"
echo "<rect width=\"1340\" height=\"1000\" fill=\"$BG\"/>"
echo "<text x=\"40\" y=\"60\" font-size=\"28\" font-weight=\"600\" fill=\"$INK\">Keeping the u readable at small sizes</text>"
for i in 0 1 2 3 4; do echo "<text x=\"${XS[$i]}\" y=\"110\" font-size=\"14\" fill=\"#7A6A5C\">${SIZES[$i]} px</text>"; done
y=200
for r in "${ROWS[@]}"; do
  IFS="|" read -r v label <<<"$r"
  echo "<text x=\"40\" y=\"$((y-20))\" font-size=\"17\" font-weight=\"600\" fill=\"$INK\">$label</text>"
  for i in 0 1 2 3 4; do word "${XS[$i]}" "$y" "${SIZES[$i]}" "$v"; done
  echo "<line x1=\"40\" y1=\"$((y+40))\" x2=\"1300\" y2=\"$((y+40))\" stroke=\"#E6DDCD\"/>"
  y=$((y+135))
done
echo "</svg>"
} > u-fix.src.svg
echo built u-fix.src.svg
