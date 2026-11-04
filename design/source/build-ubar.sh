#!/usr/bin/env bash
# Builds ubar.src.svg: the u bowl as a constant 30 bar.
# Outer edge: an eased half turn (ease 0.094) that starts exactly at the cut (x 300 and 405, y 120) and sits on the baseline.
# Inner edge: the outer edge moved exactly 30 inward along its normal, so the bar is 30 wide everywhere (measured 30.000).
# The t foot uses the frozen eased version (ease 0.25).
set -e
BG="#F9F6ED"; INK="#2B1F1A"; RED="#E0574F"; GRID="#E3D8C4"; G2="#EFE8DA"; BLUE="#5B8DEF"
FROZEN='M22.5 30 H52.5 V60 H22.5 Z M0 60 H75 V90 H0 Z M90 0 H120 V90 H90 Z M90 120 H120 V180 H90 Z M165 120 H195 V180 H165 Z M120.758 90 A37.5 37.5 0 0 1 194.242 90 Z M210 60 H240 V90 H210 Z M240 90 A30 30 0 0 1 270 60 V90 Z M270 60 H285 V90 H270 Z M210 120 H240 V180 H210 Z M300 60 H330 V90 H300 Z M375 60 H405 V90 H375 Z'
TE=$(cat parts/eased-t.txt); UC='M300 120 H330 V127.5 A22.5 22.5 0 0 0 375 127.5 V120 H405 V127.5 A52.5 52.5 0 0 1 300 127.5 Z'
UE=$(cat parts/eased-u.txt); UN=$(cat parts/u-constant.txt)
echo "<path d=\"$FROZEN $TE $UN\" fill=\"#2B1F1A\"/>" > parts/wordmark-ubar.svg
BALLS="315.55,132.87 324.25,152.07 341.97,163.48 363.05,163.48 380.76,152.05 389.45,132.85"
panel() { # x y w h vx vy vw vh path outline title balls
  local k; k=$(awk -v w=$3 -v vw=$7 'BEGIN{print w/vw}')
  echo "<rect x=\"$1\" y=\"$2\" width=\"$3\" height=\"$4\" rx=\"14\" fill=\"#FFFFFF\"/>"
  echo "<svg x=\"$1\" y=\"$2\" width=\"$3\" height=\"$4\" viewBox=\"$5 $6 $7 $8\">"
  local x; for x in $(seq 285 7.5 420); do echo "<line x1=\"$x\" y1=\"100\" x2=\"$x\" y2=\"190\" stroke=\"$( [ $(awk -v x=$x 'BEGIN{print (x%30==0)}') = 1 ] && echo $GRID || echo $G2)\" stroke-width=\"$(awk -v k=$k 'BEGIN{print 1/k}')\"/>"; done
  local y; for y in $(seq 105 7.5 190); do echo "<line x1=\"280\" y1=\"$y\" x2=\"425\" y2=\"$y\" stroke=\"$( [ $(awk -v y=$y 'BEGIN{print (y%30==0)}') = 1 ] && echo $GRID || echo $G2)\" stroke-width=\"$(awk -v k=$k 'BEGIN{print 1/k}')\"/>"; done
  echo "<path d=\"$9\" fill=\"$INK\"/>"
  [ -n "${10}" ] && echo "<path d=\"${10}\" fill=\"none\" stroke=\"$RED\" stroke-width=\"$(awk -v k=$k 'BEGIN{print 1.6/k}')\"/>"
  if [ -n "${12}" ]; then for b in ${12}; do echo "<circle cx=\"${b%,*}\" cy=\"${b#*,}\" r=\"15\" fill=\"none\" stroke=\"$BLUE\" stroke-width=\"$(awk -v k=$k 'BEGIN{print 1.4/k}')\"/>"; done; fi
  echo "</svg>"
  echo "<text x=\"$(( $1 + 14 ))\" y=\"$(( $2 + $4 + 22 ))\" font-size=\"14\" fill=\"#7A6A5C\">${11}</text>"
}
{
echo "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1400\" height=\"930\" viewBox=\"0 0 1400 930\" font-family=\"Inter\">"
echo "<rect width=\"1400\" height=\"930\" fill=\"$BG\"/>"
echo "<text x=\"40\" y=\"60\" font-size=\"28\" font-weight=\"600\" fill=\"$INK\">u bowl as a bar of constant width</text>"
echo "<text x=\"40\" y=\"88\" font-size=\"15\" fill=\"#7A6A5C\">The inner edge is the outer edge moved exactly 30 inward, so a 30 circle (blue) touches both edges everywhere. Red: today's circles.</text>"
panel 40 120 420 300 287 114 136 72 "$UC" "" "Now: circles, straight stem then curve" ""
panel 490 120 420 300 287 114 136 72 "$UE" "" "Eased 0.25: smooth, but the bar narrows" ""
panel 940 120 420 300 287 114 136 72 "$UN" "$UC" "New: one bar, 30 wide all the way" "$BALLS"
echo "<text x=\"40\" y=\"500\" font-size=\"18\" font-weight=\"600\" fill=\"$INK\">Wordmark with the frozen t foot and the new u</text>"
echo "<g transform=\"translate(40 530) scale(1.2)\" fill=\"$INK\"><path d=\"$FROZEN $TE $UN\"/></g>"
echo "<g transform=\"translate(620 610) scale(0.45)\" fill=\"$INK\"><path d=\"$FROZEN $TE $UN\"/></g>"
echo "<g transform=\"translate(860 650) scale(0.2)\" fill=\"$INK\"><path d=\"$FROZEN $TE $UN\"/></g>"
echo "<g transform=\"translate(960 662) scale(0.12)\" fill=\"$INK\"><path d=\"$FROZEN $TE $UN\"/></g>"
echo "</svg>"
} > ubar.src.svg
echo built
