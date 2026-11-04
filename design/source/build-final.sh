#!/usr/bin/env bash
# Builds final.src.svg (wordmark construction) and system.src.svg (faces, colours, card) for the design system doc.
set -e
BG="#F9F6ED"; INK="#2B1F1A"; RED="#E0574F"; GRID="#D6C9B2"; HALF="#ECE4D4"; Q="#F3EEE3"; COL="#5B8DEF"
G=$(sed 's/fill="[^"]*"//g' parts/wordmark-geo.svg)
UB=$(cat parts/u-constant.txt)
K=2.6; X0=90; Y0=150
px() { awk -v a=$1 -v s=$K -v o=$X0 'BEGIN{printf "%.2f", o+a*s}'; }
py() { awk -v a=$1 -v s=$K -v o=$Y0 'BEGIN{printf "%.2f", o+a*s}'; }
{
echo "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1400\" height=\"860\" viewBox=\"0 0 1400 860\" font-family=\"Inter\">"
echo "<rect width=\"1400\" height=\"860\" fill=\"$BG\"/>"
echo "<text x=\"40\" y=\"60\" font-size=\"28\" font-weight=\"600\" fill=\"$INK\">thru wordmark, final construction</text>"
echo "<text x=\"40\" y=\"88\" font-size=\"15\" fill=\"#7A6A5C\">Cell 30 (the t top square), split into 15 and 7.5. Height 6 cells. t 75, h 105, r 75, u 105, letters 15 apart, 405 wide.</text>"
for k in $(seq 0 54); do x=$(awk -v k=$k 'BEGIN{print k*7.5}'); c=$Q; [ $((k%2)) -eq 0 ] && c=$HALF; [ $((k%4)) -eq 0 ] && c=$GRID; echo "<line x1=\"$(px $x)\" y1=\"$(py 0)\" x2=\"$(px $x)\" y2=\"$(py 180)\" stroke=\"$c\"/>"; done
for k in $(seq 0 24); do y=$(awk -v k=$k 'BEGIN{print k*7.5}'); c=$Q; [ $((k%2)) -eq 0 ] && c=$HALF; [ $((k%4)) -eq 0 ] && c=$GRID; echo "<line x1=\"$(px 0)\" y1=\"$(py $y)\" x2=\"$(px 405)\" y2=\"$(py $y)\" stroke=\"$c\"/>"; done
for r in "0|top of h" "30|top of t" "60|x-height" "90|cut" "120|cut" "150|inner bottoms" "180|baseline"; do y=${r%%|*}; echo "<text x=\"$(px 412)\" y=\"$(awk -v a=$(py $y) 'BEGIN{print a+5}')\" font-size=\"13\" fill=\"#7A6A5C\">$y  ${r#*|}</text>"; done
echo "<rect x=\"$(px 0)\" y=\"$(py 90)\" width=\"$(awk -v s=$K 'BEGIN{print 405*s}')\" height=\"$(awk -v s=$K 'BEGIN{print 30*s}')\" fill=\"$RED\" fill-opacity=\"0.07\"/>"
echo "<g transform=\"translate($X0 $Y0) scale($K)\" fill=\"$INK\">$G</g>"
echo "<rect x=\"$(px 22.5)\" y=\"$(py 30)\" width=\"$(awk -v s=$K 'BEGIN{print 30*s}')\" height=\"$(awk -v s=$K 'BEGIN{print 30*s}')\" fill=\"none\" stroke=\"$COL\" stroke-width=\"2.5\"/>"
echo "<text x=\"$(px 22.5)\" y=\"$(awk -v a=$(py 30) 'BEGIN{print a-8}')\" font-size=\"13\" fill=\"$COL\">1 cell</text>"
for c in 157.5,97.5,37.5 270,90,30; do set -- ${c//,/ }; echo "<circle cx=\"$(px $1)\" cy=\"$(py $2)\" r=\"$(awk -v a=$3 -v s=$K 'BEGIN{print a*s}')\" fill=\"none\" stroke=\"$RED\" stroke-width=\"1.3\" stroke-opacity=\"0.8\"/>"; done
for sp in 0:75:t 90:195:h 210:285:r 300:405:u; do IFS=: read -r a b l <<<"$sp"; yb=$(awk -v v=$(py 180) 'BEGIN{print v+16}')
  echo "<path d=\"M$(px $a) $yb v6 H$(px $b) v-6\" fill=\"none\" stroke=\"$COL\" stroke-width=\"1.4\" transform=\"translate(0 0)\"/><text x=\"$(awk -v a=$(px $a) -v b=$(px $b) 'BEGIN{print (a+b)/2}')\" y=\"$(awk -v v=$yb 'BEGIN{print v+24}')\" font-size=\"13\" fill=\"$COL\" text-anchor=\"middle\">$l $((b-a))</text>"; done
echo "</svg>"
} > final.src.svg
# system sheet
EYES='<path d="M300 60 H330 V90 H300 Z M375 60 H405 V90 H375 Z"/>'
SM="<path d=\"$UB\"/>"; FR="<g transform=\"translate(0 300) scale(1 -1)\"><path d=\"$UB\"/></g>"; FL='<path d="M300 135 H405 V165 H300 Z"/>'
CL='<path d="M300 75 H330 V90 H300 Z M375 75 H405 V90 H375 Z"/>'
face() { # x y size colour mouth eyes label sub
  local k; k=$(awk -v s=$3 'BEGIN{print s*0.6/120}')
  local ox oy; ox=$(awk -v x=$1 -v s=$3 -v k=$k 'BEGIN{print x+(s-105*k)/2-300*k}'); oy=$(awk -v y=$2 -v s=$3 -v k=$k 'BEGIN{print y+(s-120*k)/2-60*k}')
  echo "<rect x=\"$1\" y=\"$2\" width=\"$3\" height=\"$3\" rx=\"$(awk -v s=$3 'BEGIN{print s*0.225}')\" fill=\"$4\"/>"
  echo "<g transform=\"translate($ox $oy) scale($k)\" fill=\"${9:-#FFFFFF}\">$6$5</g>"
  echo "<text x=\"$1\" y=\"$(( $2 + $3 + 24 ))\" font-size=\"15\" font-weight=\"600\" fill=\"$INK\">$7</text><text x=\"$1\" y=\"$(( $2 + $3 + 44 ))\" font-size=\"13\" fill=\"#7A6A5C\">$8</text>"
}
sw() { echo "<rect x=\"$1\" y=\"$2\" width=\"118\" height=\"70\" rx=\"12\" fill=\"$3\" stroke=\"#E6DDCD\"/><text x=\"$1\" y=\"$(( $2 + 92 ))\" font-size=\"14\" font-weight=\"600\" fill=\"$INK\">$4</text><text x=\"$1\" y=\"$(( $2 + 110 ))\" font-size=\"12\" fill=\"#7A6A5C\">$3</text>"; }
{
echo "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1400\" height=\"980\" viewBox=\"0 0 1400 980\" font-family=\"Inter\">"
echo "<rect width=\"1400\" height=\"980\" fill=\"$BG\"/>"
echo "<text x=\"40\" y=\"60\" font-size=\"28\" font-weight=\"600\" fill=\"$INK\">Mood face and colour</text>"
echo "<text x=\"40\" y=\"88\" font-size=\"15\" fill=\"#7A6A5C\">Faces are the final u: eyes are its two top bars, the mouth is its bowl (smile), the bowl turned over (frown) or a flat bar.</text>"
face 40 120 170 "#33B378" "$SM" "$EYES" "Push" "Recovery high"
face 250 120 170 "#EDAB2E" "$FL" "$EYES" "Moderate" "About your usual"
face 460 120 170 "#DB454C" "$FR" "$EYES" "Recover" "Below your usual"
face 670 120 170 "#9470F2" "$SM" "$CL" "Asleep" "Sleep and bedtime"
face 880 120 170 "#EFE8DA" "$SM" "$EYES" "Mono" "Ink on paper" "#2B1F1A"
echo "<g transform=\"translate(1090 120)\"><rect width=\"170\" height=\"170\" rx=\"38\" fill=\"#0D1117\"/></g>"
face 1090 120 170 "#0D1117" "$SM" "$EYES" "On dark" "Paper on dark" "#F9F6ED"
echo "<text x=\"40\" y=\"420\" font-size=\"20\" font-weight=\"600\" fill=\"$INK\">Base</text>"
sw 40 440 "#F9F6ED" "Paper"; sw 180 440 "#2B1F1A" "Ink"; sw 320 440 "#E8543D" "Accent coral"; sw 460 440 "#E02E3D" "Glow red"; sw 600 440 "#F78033" "Glow orange"; sw 740 440 "#FCC254" "Glow amber"; sw 880 440 "#0D1117" "Dark surface"
echo "<text x=\"40\" y=\"610\" font-size=\"20\" font-weight=\"600\" fill=\"$INK\">Recovery zones</text>"
sw 40 630 "#33B378" "Push"; sw 180 630 "#EDAB2E" "Moderate"; sw 320 630 "#DB454C" "Recover"
echo "<text x=\"500\" y=\"610\" font-size=\"20\" font-weight=\"600\" fill=\"$INK\">Areas</text>"
sw 500 630 "#9470F2" "Sleep"; sw 640 630 "#2978F2" "Strain"; sw 780 630 "#21A8BD" "Heart"; sw 920 630 "#F29433" "Body"; sw 1060 630 "#E3598F" "Nutrition"; sw 1200 630 "#6BBDDB" "Air"
echo "<text x=\"40\" y=\"800\" font-size=\"20\" font-weight=\"600\" fill=\"$INK\">Card</text>"
echo "<rect x=\"40\" y=\"820\" width=\"420\" height=\"130\" rx=\"24\" fill=\"#FFFFFF\" fill-opacity=\"0.6\" stroke=\"#FFFFFF\" stroke-width=\"1.5\"/>"
echo "<text x=\"64\" y=\"856\" font-size=\"14\" fill=\"#7A6A5C\">Sleep score</text><text x=\"64\" y=\"900\" font-size=\"38\" font-weight=\"600\" fill=\"$INK\">95</text><text x=\"64\" y=\"930\" font-size=\"13\" fill=\"#7A6A5C\">Radius 24 (one app cell), 24 padding, hairline edge</text>"
echo "<rect x=\"300\" y=\"850\" width=\"136\" height=\"12\" rx=\"6\" fill=\"#E6DDCD\"/><rect x=\"300\" y=\"850\" width=\"122\" height=\"12\" rx=\"6\" fill=\"#9470F2\"/>"
echo "</svg>"
} > system.src.svg
echo built
