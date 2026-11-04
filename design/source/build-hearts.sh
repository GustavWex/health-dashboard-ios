#!/usr/bin/env bash
# Builds hearts.src.svg (1600 x 800): five bolder takes on the capsule heart, each shown as an app tile,
# next to the wordmark and at favicon size. Hearts are drawn in a 1024 tile and scaled. Run from docs/source.
set -e
. ./lib.sh

# capsule <r> <x1 y1> <x2 y2> -> rect attributes (centre, length, angle) for a pill between two cap centres.
K=1.12
capsule() { awk -v k=$K -v r0=$1 -v a1=$2 -v b1=$3 -v a2=$4 -v b2=$5 'BEGIN{
  r=r0*k; x1=512+(a1-512)*k; y1=515+(b1-515)*k; x2=512+(a2-512)*k; y2=515+(b2-515)*k
  dx=x2-x1; dy=y2-y1; L=sqrt(dx*dx+dy*dy); nx=-dy/L*r; ny=dx/L*r
  printf "d=\"M%.1f %.1f L%.1f %.1f A%.1f %.1f 0 0 0 %.1f %.1f L%.1f %.1f A%.1f %.1f 0 0 0 %.1f %.1f Z\"", x1+nx,y1+ny, x2+nx,y2+ny, r,r, x2-nx,y2-ny, x1-nx,y1-ny, r,r, x1+nx,y1+ny }'; }

# heart <variant> <uid>: the heart in 1024 space. Variants: heavy solid knock cut tile.
heart() {
  local v=$1 u=$2 r L R
  case $v in
    heavy) r=178; L=$(capsule $r 338 420 512 612); R=$(capsule $r 686 420 512 612)
      echo "<clipPath id=\"ov-$u\"><path $L/></clipPath>"
      echo "<path $L fill=\"#FDB022\" fill-opacity=\"0.9\"/><path $R fill=\"#FF6F4D\" fill-opacity=\"0.9\"/>"
      echo "<path $R clip-path=\"url(#ov-$u)\" fill=\"#F03A2C\"/>";;
    solid) r=160; L=$(capsule $r 330 410 512 618); R=$(capsule $r 694 410 512 618)
      echo "<clipPath id=\"ov-$u\"><path $L/></clipPath>"
      echo "<path $L fill=\"#F7A928\"/><path $R fill=\"#E8543D\"/>"
      echo "<path $R clip-path=\"url(#ov-$u)\" fill=\"#C8302A\"/>";;
    knock) r=160; L=$(capsule $r 330 410 512 618); R=$(capsule $r 694 410 512 618)
      echo "<path $L fill=\"#E8543D\"/><path $R fill=\"#E8543D\" stroke=\"#F9F6ED\" stroke-width=\"44\"/>"
      echo "<path $R fill=\"#E8543D\"/>";;
    cut) r=165; L=$(capsule $r 330 410 512 615); R=$(capsule $r 694 410 512 615)
      echo "<path $L fill=\"#E8543D\"/><path $R fill=\"#E8543D\"/>"
      echo "<rect x=\"80\" y=\"548\" width=\"864\" height=\"50\" fill=\"#F9F6ED\"/>";;
    tile) r=160; L=$(capsule $r 330 410 512 618); R=$(capsule $r 694 410 512 618)
      echo "<clipPath id=\"ov-$u\"><path $L/></clipPath>"
      echo "<path $L fill=\"#F9F6ED\"/><path $R fill=\"#F9F6ED\"/>"
      echo "<path $R clip-path=\"url(#ov-$u)\" fill=\"#FFC24A\"/>";;
  esac
}
tilebg() { [ "$1" = tile ] && echo "#E8543D" || echo "#F9F6ED"; }

# icon <variant> <uid> <x> <y> <size>
icon() {
  local s; s=$(awk -v z=$5 'BEGIN{printf "%.5f", z/1024}')
  echo "  <g transform=\"translate($3 $4) scale($s)\">"
  echo "    <rect id=\"tile-$2\" width=\"1024\" height=\"1024\" rx=\"230\" fill=\"$(tilebg $1)\" stroke=\"#FFFFFF\" stroke-opacity=\"0.9\" stroke-width=\"$(awk -v s=$s 'BEGIN{printf "%.1f", 1.5/s}')\"/>"
  heart $1 $2 | sed 's/^/    /'
  echo "  </g>"
}

NAMES=("1  Heavier pills|heavy" "2  Solid colour|solid" "3  Knockout overlap|knock" "4  Cut heart|cut" "5  Reversed tile|tile")
BODY=""; i=0
for n in "${NAMES[@]}"; do
  IFS='|' read -r label v <<<"$n"
  x=$(( 80 + i * 292 ))
  BODY+="$(card c$i $x 110 272 560 22)
$(icon $v big$i $(( x + 36 )) 146 200)
$(icon $v mid$i $(( x + 24 )) 418 60)
$(wordmark $(( x + 24 + 60 + 15 )) 470 52)
$(icon $v sm$i $(( x + 24 )) 530 28)
$(icon $v xs$i $(( x + 64 )) 536 16)
  <text x=\"$(( x + 24 ))\" y=\"638\" font-size=\"18\" font-weight=\"600\" fill=\"#2B1F1A\">$label</text>
"
  i=$((i+1))
done

cat > hearts.src.svg <<EOF
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1600" height="740" viewBox="0 0 1600 740" font-family="Inter">
  <defs>
$(paper_defs 1600 740)
  </defs>
$(paper 1600 740 "1400 0 700" "1000 600 760" "100 760 600")
  <text x="80" y="76" font-size="34" font-weight="600" fill="#2B1F1A">Bolder heart, five directions</text>
  <image x="1352" y="44" width="48" height="48" xlink:href="$A/AppIcon.png" href="$A/AppIcon.png"/>
$(wordmark 1410 82 42)
  <text x="1290" y="76" font-size="15" fill="#7A6A5C">Now</text>
$BODY
  <text x="80" y="712" font-size="15" fill="#7A6A5C">Each shown as the app tile, next to the wordmark, and at 28 px and 16 px.</text>
</svg>
EOF
echo built hearts.src.svg
