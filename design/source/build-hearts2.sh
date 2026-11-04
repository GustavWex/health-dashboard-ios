#!/usr/bin/env bash
# Builds hearts2.src.svg (1600 x 1080): five takes on the knockout heart and five on the cut heart,
# including glassy ones with the original grain. Each shown as a tile, next to the wordmark and at 28/16 px.
set -e
. ./lib.sh
K=1.12
capsule() { awk -v k=$K -v r0=$1 -v a1=$2 -v b1=$3 -v a2=$4 -v b2=$5 'BEGIN{
  r=r0*k; x1=512+(a1-512)*k; y1=515+(b1-515)*k; x2=512+(a2-512)*k; y2=515+(b2-515)*k
  dx=x2-x1; dy=y2-y1; L=sqrt(dx*dx+dy*dy); nx=-dy/L*r; ny=dx/L*r
  printf "d=\"M%.1f %.1f L%.1f %.1f A%.1f %.1f 0 0 0 %.1f %.1f L%.1f %.1f A%.1f %.1f 0 0 0 %.1f %.1f Z\"", x1+nx,y1+ny, x2+nx,y2+ny, r,r, x2-nx,y2-ny, x1-nx,y1-ny, r,r, x1+nx,y1+ny }'; }

PAPER="#F9F6ED"; CORAL="#E8543D"; AMBER="#F7A928"; INK="#2B1F1A"
# Heart geometry (before the K scale): two pills meeting at the bottom.
geo() { L=$(capsule 160 $((330+$1)) 410 $((512+$1)) 618); R=$(capsule 160 $((694+$1)) 410 $((512+$1)) 618); }
SLIT_Y=548; SLIT_H=50

defs_glass() { # uid
  echo "<radialGradient id=\"gA-$1\" cx=\"0.3\" cy=\"0.2\" r=\"0.95\"><stop offset=\"0\" stop-color=\"#FFD54F\"/><stop offset=\"1\" stop-color=\"#FF9A1F\"/></radialGradient>"
  echo "<radialGradient id=\"gC-$1\" cx=\"0.75\" cy=\"0.2\" r=\"0.95\"><stop offset=\"0\" stop-color=\"#FF9F5E\"/><stop offset=\"1\" stop-color=\"#FF4766\"/></radialGradient>"
  echo "<radialGradient id=\"gG-$1\" cx=\"0.5\" cy=\"0.5\" r=\"0.5\"><stop offset=\"0\" stop-color=\"#FF3D6E\" stop-opacity=\"0.3\"/><stop offset=\"1\" stop-color=\"#FF3D6E\" stop-opacity=\"0\"/></radialGradient>"
}
glow() { echo "<ellipse cx=\"512\" cy=\"800\" rx=\"330\" ry=\"120\" fill=\"url(#gG-$1)\"/>"; }
grain() { echo "<clipPath id=\"h-$1\"><path $L/><path $R/></clipPath><image clip-path=\"url(#h-$1)\" x=\"0\" y=\"0\" width=\"1024\" height=\"1024\" xlink:href=\"parts/grain.png\" href=\"parts/grain.png\"/>"; }
slit() { echo "<rect x=\"60\" y=\"$SLIT_Y\" width=\"904\" height=\"$SLIT_H\" fill=\"${1:-$PAPER}\"/>"; }
halves() { echo "<clipPath id=\"top-$1\"><rect x=\"0\" y=\"0\" width=\"1024\" height=\"$SLIT_Y\"/></clipPath><clipPath id=\"bot-$1\"><rect x=\"0\" y=\"$((SLIT_Y+SLIT_H))\" width=\"1024\" height=\"$((1024-SLIT_Y-SLIT_H))\"/></clipPath>"; }

# heart <variant> <uid>
heart() {
  local v=$1 u=$2; geo 0
  case $v in
    k1) echo "<path $L fill=\"$CORAL\"/><path $R fill=\"none\" stroke=\"$PAPER\" stroke-width=\"44\"/><path $R fill=\"$CORAL\"/>";;
    k2) defs_glass $u; glow $u
        echo "<clipPath id=\"l-$u\"><path $L/></clipPath>"
        echo "<path $L fill=\"url(#gA-$u)\" fill-opacity=\"0.88\"/><path $R fill=\"url(#gC-$u)\" fill-opacity=\"0.85\"/>"
        echo "<path $R clip-path=\"url(#l-$u)\" fill=\"#F2262E\" fill-opacity=\"0.9\"/>"
        echo "<path $R clip-path=\"url(#l-$u)\" fill=\"none\" stroke=\"$PAPER\" stroke-width=\"26\"/>"; grain $u;;
    k3) echo "<path $L fill=\"$AMBER\"/><path $R fill=\"none\" stroke=\"$PAPER\" stroke-width=\"44\"/><path $R fill=\"$CORAL\"/>";;
    k4) defs_glass $u; glow $u
        echo "<path $L fill=\"url(#gA-$u)\"/><path $R fill=\"none\" stroke=\"$PAPER\" stroke-width=\"44\"/><path $R fill=\"url(#gC-$u)\"/>"; grain $u;;
    k5) echo "<path $L fill=\"$AMBER\"/><path $R fill=\"none\" stroke=\"$INK\" stroke-width=\"44\"/><path $R fill=\"$CORAL\"/>";;
    c1) echo "<path $L fill=\"$CORAL\"/><path $R fill=\"$CORAL\"/>"; slit;;
    c2) defs_glass $u; glow $u
        echo "<clipPath id=\"l-$u\"><path $L/></clipPath>"
        echo "<path $L fill=\"url(#gA-$u)\" fill-opacity=\"0.88\"/><path $R fill=\"url(#gC-$u)\" fill-opacity=\"0.85\"/>"
        echo "<path $R clip-path=\"url(#l-$u)\" fill=\"#F2262E\" fill-opacity=\"0.9\"/>"; grain $u; slit;;
    c3) halves $u; geo -48; echo "<g clip-path=\"url(#top-$u)\"><path $L fill=\"$CORAL\"/><path $R fill=\"$CORAL\"/></g>"
        geo 48; echo "<g clip-path=\"url(#bot-$u)\"><path $L fill=\"$CORAL\"/><path $R fill=\"$CORAL\"/></g>";;
    c4) halves $u; echo "<g clip-path=\"url(#top-$u)\"><path $L fill=\"$AMBER\"/><path $R fill=\"$AMBER\"/></g>"
        echo "<g clip-path=\"url(#bot-$u)\"><path $L fill=\"$CORAL\"/><path $R fill=\"$CORAL\"/></g>";;
    c5) echo "<path $L fill=\"$PAPER\"/><path $R fill=\"$PAPER\"/>"; slit $CORAL;;
  esac
}
tilebg() { case $1 in c5) echo $CORAL;; k5) echo $INK;; *) echo $PAPER;; esac; }

icon() { # variant uid x y size
  local s; s=$(awk -v z=$5 'BEGIN{printf "%.5f", z/1024}')
  echo "  <g transform=\"translate($3 $4) scale($s)\">"
  echo "    <rect width=\"1024\" height=\"1024\" rx=\"230\" fill=\"$(tilebg $1)\" stroke=\"#FFFFFF\" stroke-opacity=\"0.9\" stroke-width=\"$(awk -v s=$s 'BEGIN{printf "%.1f", 1.5/s}')\"/>"
  heart $1 $2 | sed 's/^/    /'
  echo "  </g>"
}

row() { # y title, then "label|variant" items
  local y=$1 t=$2; shift 2; local i=0 out=""
  out+="  <text x=\"80\" y=\"$((y-18))\" font-size=\"20\" font-weight=\"600\" fill=\"#7A6A5C\">$t</text>
"
  for n in "$@"; do
    IFS='|' read -r label v <<<"$n"; local x=$((80 + i*292))
    out+="$(card $v $x $y 272 410 22)
$(icon $v ${v}big $((x+36)) $((y+28)) 200)
$(icon $v ${v}mid $((x+24)) $((y+258)) 56)
$(wordmark $((x+24+56+14)) $((y+306)) 49)
$(icon $v ${v}sm $((x+24)) $((y+336)) 28)
$(icon $v ${v}xs $((x+62)) $((y+342)) 16)
  <text x=\"$((x+24))\" y=\"$((y+392))\" font-size=\"18\" font-weight=\"600\" fill=\"#2B1F1A\">$label</text>
"
    i=$((i+1))
  done
  printf '%s' "$out"
}

cat > hearts2.src.svg <<EOF
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1600" height="1080" viewBox="0 0 1600 1080" font-family="Inter">
  <defs>
$(paper_defs 1600 1080)
  </defs>
$(paper 1600 1080 "1400 0 760" "1000 700 800" "100 1100 680")
  <text x="80" y="70" font-size="34" font-weight="600" fill="#2B1F1A">Knockout and cut heart, five each</text>
  <image x="1352" y="38" width="48" height="48" xlink:href="$A/AppIcon.png" href="$A/AppIcon.png"/>
$(wordmark 1410 76 42)
  <text x="1290" y="70" font-size="15" fill="#7A6A5C">Now</text>
$(row 140 "Knockout" "K1  Flat coral|k1" "K2  Glass edge|k2" "K3  Two-tone|k3" "K4  Frosted solid|k4" "K5  On ink|k5")
$(row 610 "Cut" "C1  Flat coral|c1" "C2  Glass cut|c2" "C3  Sliced and shifted|c3" "C4  Two-tone split|c4" "C5  Reversed tile|c5")
</svg>
EOF
echo built hearts2.src.svg
