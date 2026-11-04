#!/usr/bin/env bash
# Builds ideas.src.svg: sketches for the smiley u and the heart made from the cut and the u.
# The u in local units: 112.5 wide, x-height 50 to baseline 175; eyes = the two top stubs, mouth = the bowl.
# Hearts use the wordmark circles: outer radius 50, inner 25, stroke 25; the cut is the 75-100 band.
set -e
. ./lib.sh
BG="#F9F6ED"; INK="#2B1F1A"; TILE="#EFE8DA"; CORAL="#E8553F"; GREEN="#3DAA6B"; AMBER="#F2A33A"; RED="#E0574F"
G=$(sed 's/fill="[^"]*"//g' parts/wordmark-geo-v3.svg)
EYES='<path d="M0 50 H31.25 V75 H0 Z M81.25 50 H112.5 V75 H81.25 Z"/>'
DOTS='<circle cx="15.625" cy="62.5" r="15.625"/><circle cx="96.875" cy="62.5" r="15.625"/>'
WINK='<path d="M0 56.25 H31.25 V68.75 H0 Z M81.25 50 H112.5 V75 H81.25 Z"/>'
SMILE='<path d="M0 100 H31.25 V125 A25 25 0 0 0 81.25 125 V100 H112.5 V125 A50 50 0 0 1 62.5 175 H50 A50 50 0 0 1 0 125 Z"/>'
FROWN='<g transform="translate(0 275) scale(1 -1)"><path d="M0 100 H31.25 V125 A25 25 0 0 0 81.25 125 V100 H112.5 V125 A50 50 0 0 1 62.5 175 H50 A50 50 0 0 1 0 125 Z"/></g>'
FLAT='<path d="M0 125 H112.5 V150 H0 Z"/>'
# u face centred in a tile: tile x y size face-content colour tilecolour
face() { local k; k=$(awk -v s=$3 'BEGIN{print s*0.62/125}')
  local ox oy; ox=$(awk -v x=$1 -v s=$3 -v k=$k 'BEGIN{print x+(s-112.5*k)/2}'); oy=$(awk -v y=$2 -v s=$3 -v k=$k 'BEGIN{print y+(s-125*k)/2-50*k}')
  echo "<rect x=\"$1\" y=\"$2\" width=\"$3\" height=\"$3\" rx=\"$(awk -v s=$3 'BEGIN{print s*0.225}')\" fill=\"${6:-$TILE}\"/>"
  echo "<g transform=\"translate($ox $oy) scale($k)\" fill=\"$5\">$4</g>"; }
# hearts: lobes r 50 centred (+-35.355, 50), point at 156.07; centred on x 0
HEART='M0 156.066 L-70.711 85.355 A50 50 0 0 1 0 14.645 A50 50 0 0 1 70.711 85.355 Z'
HEARTC='M0 138.388 L-53.033 85.355 A37.5 37.5 0 0 1 0 32.322 A37.5 37.5 0 0 1 53.033 85.355 Z'
heart() { # x y size kind colour tile
  local k; k=$(awk -v s=$3 'BEGIN{print s*0.62/156.07}')
  local ox oy; ox=$(awk -v x=$1 -v s=$3 'BEGIN{print x+s/2}'); oy=$(awk -v y=$2 -v s=$3 -v k=$k 'BEGIN{print y+(s-175*k)/2}')
  echo "<rect x=\"$1\" y=\"$2\" width=\"$3\" height=\"$3\" rx=\"$(awk -v s=$3 'BEGIN{print s*0.225}')\" fill=\"$6\"/>"
  echo "<g transform=\"translate($ox $oy) scale($k)\">"
  case $4 in
    solid)   echo "<path d=\"$HEART\" fill=\"$5\"/>";;
    outline) echo "<path d=\"$HEARTC\" fill=\"none\" stroke=\"$5\" stroke-width=\"25\" stroke-miterlimit=\"4\"/>";;
  esac
  echo "<rect x=\"-110\" y=\"75\" width=\"220\" height=\"25\" fill=\"$6\"/></g>"; }
cap() { echo "<text x=\"$1\" y=\"$2\" font-size=\"16\" font-weight=\"600\" fill=\"$INK\">$3</text><text x=\"$1\" y=\"$(( $2 + 21 ))\" font-size=\"13\" fill=\"#7A6A5C\">$4</text>"; }
wm() { local s y; s=$(awk -v f=$3 'BEGIN{printf "%.5f", f/250}'); y=$(awk -v b=$2 -v f=$3 'BEGIN{printf "%.2f", b-175*f/250}'); echo "<g transform=\"translate($1 $y) scale($s)\" fill=\"$INK\">$G</g>"; }
{
echo "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" width=\"1400\" height=\"1180\" viewBox=\"0 0 1400 1180\" font-family=\"Inter\">"
echo "<rect width=\"1400\" height=\"1180\" fill=\"$BG\"/>"
echo "<text x=\"40\" y=\"60\" font-size=\"28\" font-weight=\"600\" fill=\"$INK\">Two logo ideas from the wordmark</text>"
echo "<text x=\"40\" y=\"118\" font-size=\"20\" font-weight=\"600\" fill=\"$INK\">1  The u is a smiley</text>"
face 40 140 220 "$EYES$SMILE" "$INK";            cap 40 390 "a  As drawn" "Stubs are the eyes, the cut is the gap"
face 290 140 220 "$DOTS$SMILE" "$INK";           cap 290 390 "b  Round eyes" "Eyes become dots, 1 stroke wide"
face 540 140 220 "$WINK$SMILE" "$BG" "$CORAL";   cap 540 390 "c  Wink" "Half-height eye, for done and saved"
face 790 140 140 "$EYES$SMILE" "#FFFFFF" "$GREEN"; face 940 140 140 "$EYES$FLAT" "#FFFFFF" "$AMBER"; face 1090 140 140 "$EYES$FROWN" "#FFFFFF" "$RED"
cap 790 310 "d  Moods" "Smile, flat, frown: good, steady, take it easy"
wm 790 450 120; echo "<g transform=\"translate($(awk 'BEGIN{print 790+336.154*120/250}') $(awk 'BEGIN{print 450-175*120/250}')) scale($(awk 'BEGIN{print 120/250}')) translate(-336.154 0)\" fill=\"$CORAL\"><path d=\"M336.154 50 H367.404 V75 H336.154 Z M417.404 50 H448.654 V75 H417.404 Z M336.154 100 H367.404 V125 A25 25 0 0 0 417.404 125 V100 H448.654 V125 A50 50 0 0 1 398.654 175 H386.154 A50 50 0 0 1 336.154 125 Z\"/></g>"
cap 1040 410 "e  In the wordmark" "Only the u in colour"
echo "<text x=\"40\" y=\"520\" font-size=\"20\" font-weight=\"600\" fill=\"$INK\">2  A heart from the cut and the u</text>"
heart 40 542 220 solid "$CORAL" "$TILE";          cap 40 792 "a  Cut heart" "Lobes r 50, the cut runs through"
heart 290 542 220 outline "$CORAL" "$TILE";       cap 290 792 "b  u-bowl heart" "Each lobe is the u bowl turned over"
heart 540 542 220 solid "$BG" "$CORAL";           cap 540 792 "c  Reversed" "Paper heart on coral, app icon"
echo "<rect x=\"790\" y=\"542\" width=\"220\" height=\"220\" rx=\"49.5\" fill=\"$TILE\"/>"
echo "<clipPath id=\"iconclip\"><rect x=\"810\" y=\"562\" width=\"180\" height=\"180\" rx=\"40\"/></clipPath><image clip-path=\"url(#iconclip)\" x=\"810\" y=\"562\" width=\"180\" height=\"180\" xlink:href=\"$A/AppIcon.png\" href=\"$A/AppIcon.png\"/>"
echo "<rect x=\"800\" y=\"$(awk 'BEGIN{print 562+180*75/175}')\" width=\"200\" height=\"$(awk 'BEGIN{print 180*25/175}')\" fill=\"$TILE\"/>"
cap 790 792 "d  Glass icon, cut" "The current heart with the same slit"
# lockup: heart on the same grid as the word, one cut through both
LX=40; LY=880; F=180; s=$(awk -v f=$F 'BEGIN{print f/250}')
echo "<rect x=\"$LX\" y=\"$LY\" width=\"1320\" height=\"230\" rx=\"22\" fill=\"$TILE\"/>"
echo "<g transform=\"translate($(awk -v x=$LX -v s=$s 'BEGIN{print x+60+70.711*s}') $((LY+30))) scale($s)\" fill=\"$CORAL\"><path d=\"$HEART\"/></g>"
echo "<g transform=\"translate($(awk -v x=$LX -v s=$s 'BEGIN{print x+60+141.42*s+60}') $((LY+30))) scale($s)\" fill=\"$INK\">$G</g>"
echo "<rect x=\"$((LX+20))\" y=\"$(awk -v y=$LY -v s=$s 'BEGIN{print y+30+75*s}')\" width=\"900\" height=\"$(awk -v s=$s 'BEGIN{print 25*s}')\" fill=\"$TILE\"/>"
cap 1000 960 "e  One line through both" "Heart and word on the same 7-module grid,"
echo "<text x=\"1000\" y=\"1002\" font-size=\"13\" fill=\"#7A6A5C\">so a single cut runs through the whole lockup</text>"
echo "</svg>"
} > ideas.src.svg
echo built
