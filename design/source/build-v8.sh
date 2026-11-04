#!/usr/bin/env bash
# Builds v8.src.svg on the 7.5 grid (the t top square, 30, split twice).
# t 75 wide (7.5 off each side of the 90 version), stem centred, foot ring r45/r15 then a bar to 75.
# h arch: a perfect half circle, diameter 75 (stem edge to leg outer edge).
#   1: flat side on the top of the cut (y 90): touches the stem in a point, top 7.5 above the x-height.
#   2: same circle centred on y 97.5: top on the x-height, the cut hides its lowest 7.5.
# r (variant B): quarter of an r30 circle plus a 15 bar, 75 wide, the same as the t.
set -e
BG="#F9F6ED"; INK="#2B1F1A"; RED="#E0574F"; GRID="#D6C9B2"; HALF="#ECE4D4"; Q="#F3EEE3"; COL="#5B8DEF"
geo() { local s y; s=$(awk -v f=$3 'BEGIN{printf "%.5f", f/250}'); y=$(awk -v b=$2 -v f=$3 'BEGIN{printf "%.2f", b-180*f/250}'); echo "<g transform=\"translate($1 $y) scale($s)\" fill=\"$INK\">$4</g>"; }
ROWS=("v8|1  Half circle on the cut|Diameter 75, flat side on the cut, touches the stem in a point; its top sits 7.5 above the x-height|67.5,135,45 67.5,135,15 157.5,90,37.5 270,90,30 352.5,127.5,52.5 352.5,127.5,22.5"
      "v8b|2  Half circle on the x-height|Same circle moved down 7.5: top on the x-height, the cut hides the bottom 7.5 of the half|67.5,135,45 67.5,135,15 157.5,97.5,37.5 270,90,30 352.5,127.5,52.5 352.5,127.5,22.5")
K=1.6
{
echo "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1400\" height=\"880\" viewBox=\"0 0 1400 880\" font-family=\"Inter\">"
echo "<rect width=\"1400\" height=\"880\" fill=\"$BG\"/>"
echo "<text x=\"40\" y=\"60\" font-size=\"28\" font-weight=\"600\" fill=\"$INK\">t at 75, h arch a half circle</text>"
echo "<text x=\"40\" y=\"88\" font-size=\"15\" fill=\"#7A6A5C\">Grid: the t top square (30) split into 15s and 7.5s. t 75, h 105, r 75, u 105, letters 15 apart, width 405.</text>"
y=110
for r in "${ROWS[@]}"; do
  IFS="|" read -r f title note circles <<<"$r"
  G=$(sed 's/fill="[^"]*"//g' parts/wordmark-$f.svg)
  X0=60; Y0=$((y+80))
  px() { awk -v a=$1 -v s=$K -v o=$X0 'BEGIN{printf "%.2f", o+a*s}'; }
  py() { awk -v a=$1 -v s=$K -v o=$Y0 'BEGIN{printf "%.2f", o+a*s}'; }
  echo "<text x=\"40\" y=\"$((y+24))\" font-size=\"18\" font-weight=\"600\" fill=\"$INK\">$title</text>"
  echo "<text x=\"40\" y=\"$((y+46))\" font-size=\"13\" fill=\"#7A6A5C\">$note</text>"
  for k in $(seq 0 54); do x=$(awk -v k=$k 'BEGIN{print k*7.5}'); c=$Q; [ $((k%2)) -eq 0 ] && c=$HALF; [ $((k%4)) -eq 0 ] && c=$GRID; echo "<line x1=\"$(px $x)\" y1=\"$(py 0)\" x2=\"$(px $x)\" y2=\"$(py 180)\" stroke=\"$c\"/>"; done
  for k in $(seq 0 24); do yy=$(awk -v k=$k 'BEGIN{print k*7.5}'); c=$Q; [ $((k%2)) -eq 0 ] && c=$HALF; [ $((k%4)) -eq 0 ] && c=$GRID; echo "<line x1=\"$(px 0)\" y1=\"$(py $yy)\" x2=\"$(px 405)\" y2=\"$(py $yy)\" stroke=\"$c\"/>"; done
  echo "<line x1=\"$(px 0)\" y1=\"$(py 60)\" x2=\"$(px 405)\" y2=\"$(py 60)\" stroke=\"$COL\" stroke-opacity=\"0.6\" stroke-dasharray=\"5 4\"/>"
  echo "<text x=\"$(px 412)\" y=\"$(awk -v a=$(py 60) 'BEGIN{print a+4}')\" font-size=\"12\" fill=\"$COL\">x-height</text>"
  echo "<rect x=\"$(px 0)\" y=\"$(py 90)\" width=\"$(awk -v s=$K 'BEGIN{print 405*s}')\" height=\"$(awk -v s=$K 'BEGIN{print 30*s}')\" fill=\"$RED\" fill-opacity=\"0.06\"/>"
  echo "<g transform=\"translate($X0 $Y0) scale($K)\" fill=\"$INK\">$G</g>"
  for c in $circles; do set -- ${c//,/ }
    echo "<circle cx=\"$(px $1)\" cy=\"$(py $2)\" r=\"$(awk -v a=$3 -v s=$K 'BEGIN{print a*s}')\" fill=\"none\" stroke=\"$RED\" stroke-width=\"1\" stroke-opacity=\"0.75\"/>"
  done
  geo 780 $((y+260)) 150 "$G"; geo 1060 $((y+240)) 56 "$G"; geo 1220 $((y+230)) 28 "$G"
  echo "<line x1=\"40\" y1=\"$((y+370))\" x2=\"1360\" y2=\"$((y+370))\" stroke=\"#E6DDCD\"/>"
  y=$((y+380))
done
echo "</svg>"
} > v8.src.svg
echo built
