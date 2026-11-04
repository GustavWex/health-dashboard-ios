#!/usr/bin/env bash
# Builds u-sharp.src.svg: three cleaner bowl constructions for the u (and the t foot, which shares it).
# Now:  outer = two r50 quarters + 12.5 flat, inner r25 on another centre (stroke wobbles).
# A: one ring, outer r56.25 and inner r25 on the same centre (y 125), stroke 31.25 all round, dips 6.25 below the baseline.
# B: outer semicircle r56.25 sitting on the baseline (centre y 118.75), inner r25 on y 125: sides 31.25, bottom 25 like the bars.
# C: one ring sitting on the baseline (both centres y 118.75), stroke 31.25 all round, inner bottom at 143.75.
set -e
BG="#F9F6ED"; INK="#2B1F1A"; RED="#E0574F"; GRID="#D9CDB8"
M=$(grep -o 'd="[^"]*"' parts/wordmark-geo-v3.svg | sed 's/^d="//; s/"$//')
T0='M25 100 H56.25 V125 A25 25 0 0 0 81.25 150 H87.5 V175 H75 A50 50 0 0 1 25 125 Z'
U0='M336.154 100 H367.404 V125 A25 25 0 0 0 417.404 125 V100 H448.654 V125 A50 50 0 0 1 398.654 175 H386.154 A50 50 0 0 1 336.154 125 Z'
TA='M25 100 H56.25 V125 A25 25 0 0 0 81.25 150 H87.5 V180.902 A56.25 56.25 0 0 1 25 125 Z'
UA='M336.154 100 H367.404 V125 A25 25 0 0 0 417.404 125 V100 H448.654 V125 A56.25 56.25 0 0 1 336.154 125 Z'
TB='M25 100 H56.25 V125 A25 25 0 0 0 81.25 150 H87.5 V174.652 A56.25 56.25 0 0 1 25 118.75 Z'
UB='M336.154 100 H367.404 V125 A25 25 0 0 0 417.404 125 V100 H448.654 V118.75 A56.25 56.25 0 0 1 336.154 118.75 Z'
TC='M25 100 H56.25 V118.75 A25 25 0 0 0 81.25 143.75 H87.5 V174.652 A56.25 56.25 0 0 1 25 118.75 Z'
UC='M336.154 100 H367.404 V118.75 A25 25 0 0 0 417.404 118.75 V100 H448.654 V118.75 A56.25 56.25 0 0 1 336.154 118.75 Z'
variant() { local d="${M/$T0/$1}"; echo "${d/$U0/$2}"; }
DN="$M"; DA=$(variant "$TA" "$UA"); DB=$(variant "$TB" "$UB"); DC=$(variant "$TC" "$UC")
[ "$DA" != "$M" ] && [ "$DB" != "$M" ] || { echo "substitution failed"; exit 1; }
for v in A B C; do eval "d=\$D$v"; echo "<path d=\"$d\" fill=\"#2B1F1A\"/>" > parts/wordmark-geo-$v.svg; done
geo() { local s y; s=$(awk -v f=$3 'BEGIN{printf "%.5f", f/250}'); y=$(awk -v b=$2 -v f=$3 'BEGIN{printf "%.2f", b-175*f/250}'); echo "<g transform=\"translate($1 $y) scale($s)\" fill=\"$INK\"><path d=\"$4\"/></g>"; }
circ() { # X0 Y0 K cx cy r
  echo "<circle cx=\"$(awk -v a=$4 -v s=$3 -v o=$1 'BEGIN{print o+a*s}')\" cy=\"$(awk -v a=$5 -v s=$3 -v o=$2 'BEGIN{print o+a*s}')\" r=\"$(awk -v a=$6 -v s=$3 'BEGIN{print a*s}')\" fill=\"none\" stroke=\"$RED\" stroke-width=\"1.2\"/><circle cx=\"$(awk -v a=$4 -v s=$3 -v o=$1 'BEGIN{print o+a*s}')\" cy=\"$(awk -v a=$5 -v s=$3 -v o=$2 'BEGIN{print o+a*s}')\" r=\"2.5\" fill=\"$RED\"/>"; }
ROWS=("N|Now|Outer: two r50 quarters and a flat. Inner: r25 on another centre. Stroke wobbles."
      "A|A  One ring, overshoot|Outer r56.25 and inner r25 share a centre on y 125. Even 31.25 stroke; dips 6.25 below the baseline like a round letter should."
      "B|B  Two semicircles, contrast|Outer r56.25 sits on the baseline, inner r25 on y 125. Sides 31.25, bottom 25, the same contrast as stems and bars."
      "C|C  One ring on the baseline|Both on y 118.75. Even 31.25 stroke, no overshoot; inner bottom moves off the grid to 143.75.")
{
echo "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1400\" height=\"1330\" viewBox=\"0 0 1400 1330\" font-family=\"Inter\">"
echo "<rect width=\"1400\" height=\"1330\" fill=\"$BG\"/>"
echo "<text x=\"40\" y=\"60\" font-size=\"28\" font-weight=\"600\" fill=\"$INK\">Sharpening the u (and the t foot)</text>"
y=110
for r in "${ROWS[@]}"; do
  IFS="|" read -r v title note <<<"$r"
  eval "d=\$D$v"
  echo "<text x=\"40\" y=\"$((y+20))\" font-size=\"18\" font-weight=\"600\" fill=\"$INK\">$title</text>"
  echo "<text x=\"40\" y=\"$((y+42))\" font-size=\"13\" fill=\"#7A6A5C\">$note</text>"
  K=1.15; X0=40; Y0=$((y+60))
  for gy in 0 50 75 100 125 150 175; do echo "<line x1=\"30\" y1=\"$(awk -v o=$Y0 -v a=$gy -v s=$K 'BEGIN{print o+a*s}')\" x2=\"570\" y2=\"$(awk -v o=$Y0 -v a=$gy -v s=$K 'BEGIN{print o+a*s}')\" stroke=\"$GRID\"/>"; done
  echo "<g transform=\"translate($X0 $Y0) scale($K)\" fill=\"$INK\"><path d=\"$d\"/></g>"
  case $v in
    N) circ $X0 $Y0 $K 75 125 50; circ $X0 $Y0 $K 81.25 125 25; circ $X0 $Y0 $K 386.154 125 50; circ $X0 $Y0 $K 398.654 125 50; circ $X0 $Y0 $K 392.404 125 25;;
    A) circ $X0 $Y0 $K 81.25 125 56.25; circ $X0 $Y0 $K 81.25 125 25; circ $X0 $Y0 $K 392.404 125 56.25; circ $X0 $Y0 $K 392.404 125 25;;
    B) circ $X0 $Y0 $K 81.25 118.75 56.25; circ $X0 $Y0 $K 81.25 125 25; circ $X0 $Y0 $K 392.404 118.75 56.25; circ $X0 $Y0 $K 392.404 125 25;;
    C) circ $X0 $Y0 $K 81.25 118.75 56.25; circ $X0 $Y0 $K 81.25 118.75 25; circ $X0 $Y0 $K 392.404 118.75 56.25; circ $X0 $Y0 $K 392.404 118.75 25;;
  esac
  geo 640 $((y+255)) 120 "$d"; geo 920 $((y+235)) 64 "$d"; geo 1100 $((y+225)) 32 "$d"; geo 1220 $((y+221)) 24 "$d"
  echo "<line x1=\"40\" y1=\"$((y+290))\" x2=\"1360\" y2=\"$((y+290))\" stroke=\"#E6DDCD\"/>"
  y=$((y+305))
done
echo "</svg>"
} > u-sharp.src.svg
echo built
