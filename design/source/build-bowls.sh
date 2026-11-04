#!/usr/bin/env bash
# Builds bowls.src.svg: the t foot and u bowl zoomed, circles (now) against eased curves.
# Eased = curvature ramps in from zero where the curve leaves the straight edge (ease 0.25), same grid end points.
set -e
BG="#F9F6ED"; INK="#2B1F1A"; RED="#E0574F"; GRID="#E3D8C4"; G2="#EFE8DA"
FROZEN='M22.5 30 H52.5 V60 H22.5 Z M0 60 H75 V90 H0 Z M90 0 H120 V90 H90 Z M90 120 H120 V180 H90 Z M165 120 H195 V180 H165 Z M120.758 90 A37.5 37.5 0 0 1 194.242 90 Z M210 60 H240 V90 H210 Z M240 90 A30 30 0 0 1 270 60 V90 Z M270 60 H285 V90 H270 Z M210 120 H240 V180 H210 Z M300 60 H330 V90 H300 Z M375 60 H405 V90 H375 Z'
TC='M22.5 120 H52.5 V135 A15 15 0 0 0 67.5 150 H75 V180 H67.5 A45 45 0 0 1 22.5 135 Z'
UC='M300 120 H330 V127.5 A22.5 22.5 0 0 0 375 127.5 V120 H405 V127.5 A52.5 52.5 0 0 1 300 127.5 Z'
TE=$(cat parts/eased-t.txt); UE=$(cat parts/eased-u.txt)
echo "<path d=\"$FROZEN $TE $UE\" fill=\"#2B1F1A\"/>" > parts/wordmark-eased.svg
panel() { # x y w h  vx vy vw vh  fillpath outlinepath title
  local k; k=$(awk -v w=$3 -v vw=$7 'BEGIN{print w/vw}')
  echo "<rect x=\"$1\" y=\"$2\" width=\"$3\" height=\"$4\" rx=\"14\" fill=\"#FFFFFF\"/>"
  echo "<svg x=\"$1\" y=\"$2\" width=\"$3\" height=\"$4\" viewBox=\"$5 $6 $7 $8\">"
  local x; for x in $(seq 0 7.5 420); do echo "<line x1=\"$x\" y1=\"0\" x2=\"$x\" y2=\"190\" stroke=\"$( [ $(awk -v x=$x 'BEGIN{print (x%30==0)}') = 1 ] && echo $GRID || echo $G2)\" stroke-width=\"$(awk -v k=$k 'BEGIN{print 1/k}')\"/>"; done
  local y; for y in $(seq 0 7.5 190); do echo "<line x1=\"0\" y1=\"$y\" x2=\"420\" y2=\"$y\" stroke=\"$( [ $(awk -v y=$y 'BEGIN{print (y%30==0)}') = 1 ] && echo $GRID || echo $G2)\" stroke-width=\"$(awk -v k=$k 'BEGIN{print 1/k}')\"/>"; done
  echo "<path d=\"$9\" fill=\"$INK\"/>"
  [ -n "${10}" ] && echo "<path d=\"${10}\" fill=\"none\" stroke=\"$RED\" stroke-width=\"$(awk -v k=$k 'BEGIN{print 1.6/k}')\"/>"
  echo "</svg>"
  echo "<text x=\"$(( $1 + 14 ))\" y=\"$(( $2 + $4 - 14 ))\" font-size=\"14\" fill=\"#7A6A5C\">${11}</text>"
}
{
echo "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1400\" height=\"1140\" viewBox=\"0 0 1400 1140\" font-family=\"Inter\">"
echo "<rect width=\"1400\" height=\"1140\" fill=\"$BG\"/>"
echo "<text x=\"40\" y=\"60\" font-size=\"28\" font-weight=\"600\" fill=\"$INK\">t foot and u bowl, zoomed</text>"
echo "<text x=\"40\" y=\"88\" font-size=\"15\" fill=\"#7A6A5C\">Left: circles, as now. Right: eased curves that start with no curvature and build up, filled, with today's circles as a red line on top.</text>"
panel 40 110 640 440 -14 112 105 72 "$TC" "" "t foot now: circle meets the straight edge at full curvature"
panel 720 110 640 440 -14 112 105 72 "$TE" "$TC" "t foot eased: same end points, the turn starts gently"
panel 40 580 640 340 287 114 136 72 "$UC" "" "u bowl now: 7.5 of straight stem, then a circle"
panel 720 580 640 340 287 114 136 72 "$UE" "$UC" "u bowl eased: one continuous curve from the cut down"
echo "<text x=\"40\" y=\"970\" font-size=\"18\" font-weight=\"600\" fill=\"$INK\">At size, now and eased</text>"
for i in 0 1; do
  [ $i = 0 ] && D="$FROZEN $TC $UC" || D="$FROZEN $TE $UE"
  x=$((40 + i*680))
  echo "<g transform=\"translate($x 990) scale(0.6)\" fill=\"$INK\"><path d=\"$D\"/></g>"
  echo "<g transform=\"translate($((x+290)) 1040) scale(0.2)\" fill=\"$INK\"><path d=\"$D\"/></g>"
  echo "<g transform=\"translate($((x+400)) 1050) scale(0.12)\" fill=\"$INK\"><path d=\"$D\"/></g>"
done
echo "</svg>"
} > bowls.src.svg
echo built
