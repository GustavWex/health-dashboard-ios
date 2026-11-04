#!/usr/bin/env bash
# Builds geo.src.svg: the master wordmark, square grid plus mood face proportions.
# Cell = the t top square (30 x 30), split into four 15 squares. Stems and bars = one cell.
# 12 small squares tall: h top 0, t top 30, x-height 60, crossbar 60-90, cut 90-120, baseline 180.
# Mood face proportions: stem / height about 0.17, u width / x-height part about 0.9.
# Widths: t = r = 60 (4 small squares); h = u = 105 (7). Letters 15 apart (one small square).
# Curves (every end point and tangent on a grid line):
#   h arch: slice of an r38.44 circle through (stem edge, 90), (leg outer edge, 90), top at the x-height. Pointed both ends.
#   r arm:  the same circle, pointed at the stem, cut flat at the r's right edge (60 wide).
#   u bowl: ring r52.5 / r22.5 centred on (322.5, 127.5), even 30 stroke, on the baseline.
#   t foot: ring r45 / r15 centred on (60, 135), ending square at its centre.
set -e
BG="#F9F6ED"; INK="#2B1F1A"; RED="#E0574F"; GRID="#D6C9B2"; HALF="#ECE4D4"; COL="#5B8DEF"
G=$(sed 's/fill="[^"]*"//g' parts/wordmark-geo-v7.svg)
geo() { local s y; s=$(awk -v f=$3 'BEGIN{printf "%.5f", f/250}'); y=$(awk -v b=$2 -v f=$3 'BEGIN{printf "%.2f", b-180*f/250}'); echo "<g transform=\"translate($1 $y) scale($s)\" fill=\"${4:-$INK}\">$G</g>"; }
X0=150; Y0=170; K=2.6
px() { awk -v a=$1 -v s=$K -v o=$X0 'BEGIN{printf "%.2f", o+a*s}'; }
py() { awk -v a=$1 -v s=$K -v o=$Y0 'BEGIN{printf "%.2f", o+a*s}'; }
bracket() { local a b; a=$(px $1); b=$(px $2)
  echo "<path d=\"M$a $(( $3 - 6 )) V$3 H$b V$(( $3 - 6 ))\" fill=\"none\" stroke=\"$COL\" stroke-width=\"1.5\"/>"
  echo "<text x=\"$(awk -v a=$a -v b=$b 'BEGIN{print (a+b)/2}')\" y=\"$(( $3 + 18 ))\" font-size=\"13\" fill=\"$COL\" text-anchor=\"middle\">$4</text>"; }
{
echo "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1400\" height=\"1100\" viewBox=\"0 0 1400 1100\" font-family=\"Inter\">"
echo "<rect width=\"1400\" height=\"1100\" fill=\"$BG\"/>"
echo "<text x=\"40\" y=\"60\" font-size=\"28\" font-weight=\"600\" fill=\"$INK\">thru on a square grid, mood face proportions</text>"
echo "<text x=\"40\" y=\"88\" font-size=\"15\" fill=\"#7A6A5C\">One cell = the t top square (30), split into four 15 squares. 12 small squares tall. t and r 4 wide, h and u 7 wide, letters 1 apart.</text>"
for k in $(seq 0 25); do x=$((k*15)); c=$HALF; [ $((k%2)) -eq 0 ] && c=$GRID; echo "<line x1=\"$(px $x)\" y1=\"$(py 0)\" x2=\"$(px $x)\" y2=\"$(py 180)\" stroke=\"$c\"/>"; done
for k in $(seq 0 12); do y=$((k*15)); c=$HALF; [ $((k%2)) -eq 0 ] && c=$GRID; echo "<line x1=\"$(px 0)\" y1=\"$(py $y)\" x2=\"$(px 375)\" y2=\"$(py $y)\" stroke=\"$c\"/><text x=\"$(px 383)\" y=\"$(awk -v a=$(py $y) 'BEGIN{print a+5}')\" font-size=\"12\" fill=\"#7A6A5C\">$k</text>"; done
echo "<rect x=\"$(px 0)\" y=\"$(py 90)\" width=\"$(awk -v s=$K 'BEGIN{print 375*s}')\" height=\"$(awk -v s=$K 'BEGIN{print 30*s}')\" fill=\"$RED\" fill-opacity=\"0.06\"/>"
echo "<g transform=\"translate($X0 $Y0) scale($K)\" fill=\"$INK\">$G</g>"
echo "<rect x=\"$(px 15)\" y=\"$(py 30)\" width=\"$(awk -v s=$K 'BEGIN{print 30*s}')\" height=\"$(awk -v s=$K 'BEGIN{print 30*s}')\" fill=\"none\" stroke=\"$COL\" stroke-width=\"2.5\"/>"
echo "<text x=\"$(px 15)\" y=\"$(awk -v a=$(py 30) 'BEGIN{print a-8}')\" font-size=\"13\" fill=\"$COL\">1 cell</text>"
for c in 60,135,45 60,135,15 142.5,98.4375,38.4375 262.5,98.4375,38.4375 322.5,127.5,52.5 322.5,127.5,22.5; do
  set -- ${c//,/ }
  echo "<circle cx=\"$(px $1)\" cy=\"$(py $2)\" r=\"$(awk -v a=$3 -v s=$K 'BEGIN{print a*s}')\" fill=\"none\" stroke=\"$RED\" stroke-width=\"1.2\" stroke-opacity=\"0.8\"/><circle cx=\"$(px $1)\" cy=\"$(py $2)\" r=\"3\" fill=\"$RED\"/>"
done
by=$(awk -v a=$(py 180) 'BEGIN{printf "%d", a+30}')
bracket 0 60 $by "t 4"; bracket 75 180 $by "h 7"; bracket 195 255 $by "r 4"; bracket 270 375 $by "u 7"
y=800
echo "<text x=\"40\" y=\"$y\" font-size=\"18\" font-weight=\"600\" fill=\"$INK\">At size</text>"
geo 80 $((y+170)) 200; geo 470 $((y+125)) 80; geo 690 $((y+110)) 32; geo 810 $((y+105)) 24
echo "<rect x=\"920\" y=\"$((y+40))\" width=\"440\" height=\"180\" rx=\"16\" fill=\"#0D1117\"/>"
geo 960 $((y+165)) 120 "$BG"; geo 1240 $((y+145)) 32 "$BG"
echo "</svg>"
} > geo.src.svg
echo built
