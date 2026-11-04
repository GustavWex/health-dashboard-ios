#!/usr/bin/env bash
# Builds tweaks.src.svg: the baseline wordmark against two tweaked versions, on the 15 grid (cell = 30, the t top square).
# Tweaks: t 90 wide (cross of four cells, centred stem, foot extended to 90);
#         h arch = top half of an r45 circle (diameter 3 cells) halved by the middle of the cut, right side on the leg;
#         r arm = quarter of an r30 circle (diameter 2 cells), then A: one full cell (r = t = 90) or B: half a cell (r 75).
set -e
BG="#F9F6ED"; INK="#2B1F1A"; RED="#E0574F"; GRID="#D6C9B2"; HALF="#ECE4D4"; COL="#5B8DEF"
geo() { local s y; s=$(awk -v f=$3 'BEGIN{printf "%.5f", f/250}'); y=$(awk -v b=$2 -v f=$3 'BEGIN{printf "%.2f", b-180*f/250}'); echo "<g transform=\"translate($1 $y) scale($s)\" fill=\"${5:-$INK}\">$4</g>"; }
ROWS=("baseline|Baseline|t 60, h arch a pointed slice, r arm from the same circle, r 60|60,135,45 60,135,15 142.5,98.4375,38.4375 262.5,98.4375,38.4375 322.5,127.5,52.5 322.5,127.5,22.5|0:60 75:180 195:255 270:375"
      "rA|A  r ends in a full cell|t 90, h half circle d90, r quarter circle d60 plus one cell: r = t = 90|75,135,45 75,135,15 165,105,45 165,105,15 285,90,30 382.5,127.5,52.5 382.5,127.5,22.5|0:90 105:210 225:315 330:435"
      "rB|B  r ends in half a cell|Same, but the r ends in a 15 wide bar: r 75, t 90|75,135,45 75,135,15 165,105,45 165,105,15 285,90,30 367.5,127.5,52.5 367.5,127.5,22.5|0:90 105:210 225:300 315:420")
K=1.45
{
echo "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1400\" height=\"1200\" viewBox=\"0 0 1400 1200\" font-family=\"Inter\">"
echo "<rect width=\"1400\" height=\"1200\" fill=\"$BG\"/>"
echo "<text x=\"40\" y=\"60\" font-size=\"28\" font-weight=\"600\" fill=\"$INK\">Baseline and two tweaks</text>"
y=100
for r in "${ROWS[@]}"; do
  IFS="|" read -r f title note circles spans <<<"$r"
  G=$(sed 's/fill="[^"]*"//g' parts/wordmark-$f.svg)
  X0=60; Y0=$((y+70))
  px() { awk -v a=$1 -v s=$K -v o=$X0 'BEGIN{printf "%.2f", o+a*s}'; }
  py() { awk -v a=$1 -v s=$K -v o=$Y0 'BEGIN{printf "%.2f", o+a*s}'; }
  echo "<text x=\"40\" y=\"$((y+24))\" font-size=\"18\" font-weight=\"600\" fill=\"$INK\">$title</text>"
  echo "<text x=\"40\" y=\"$((y+46))\" font-size=\"13\" fill=\"#7A6A5C\">$note</text>"
  for k in $(seq 0 29); do x=$((k*15)); c=$HALF; [ $((k%2)) -eq 0 ] && c=$GRID; echo "<line x1=\"$(px $x)\" y1=\"$(py 0)\" x2=\"$(px $x)\" y2=\"$(py 180)\" stroke=\"$c\"/>"; done
  for k in $(seq 0 12); do yy=$((k*15)); c=$HALF; [ $((k%2)) -eq 0 ] && c=$GRID; echo "<line x1=\"$(px 0)\" y1=\"$(py $yy)\" x2=\"$(px 435)\" y2=\"$(py $yy)\" stroke=\"$c\"/>"; done
  echo "<rect x=\"$(px 0)\" y=\"$(py 90)\" width=\"$(awk -v s=$K 'BEGIN{print 435*s}')\" height=\"$(awk -v s=$K 'BEGIN{print 30*s}')\" fill=\"$RED\" fill-opacity=\"0.06\"/>"
  echo "<g transform=\"translate($X0 $Y0) scale($K)\" fill=\"$INK\">$G</g>"
  for c in $circles; do set -- ${c//,/ }
    echo "<circle cx=\"$(px $1)\" cy=\"$(py $2)\" r=\"$(awk -v a=$3 -v s=$K 'BEGIN{print a*s}')\" fill=\"none\" stroke=\"$RED\" stroke-width=\"1\" stroke-opacity=\"0.75\"/>"
  done
  for sp in $spans; do a=${sp%%:*}; b=${sp##*:}
    echo "<path d=\"M$(px $a) $(awk -v v=$(py 180) 'BEGIN{print v+10}') v6 H$(px $b) v-6\" fill=\"none\" stroke=\"$COL\" stroke-width=\"1.3\"/>"
    echo "<text x=\"$(awk -v a=$(px $a) -v b=$(px $b) 'BEGIN{print (a+b)/2}')\" y=\"$(awk -v v=$(py 180) 'BEGIN{print v+30}')\" font-size=\"12\" fill=\"$COL\" text-anchor=\"middle\">$((b-a))</text>"
  done
  geo 760 $((y+230)) 150 "$G"; geo 1060 $((y+215)) 56 "$G"; geo 1220 $((y+205)) 28 "$G"
  echo "<line x1=\"40\" y1=\"$((y+350))\" x2=\"1360\" y2=\"$((y+350))\" stroke=\"#E6DDCD\"/>"
  y=$((y+360))
done
echo "</svg>"
} > tweaks.src.svg
echo built
