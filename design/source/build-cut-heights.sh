#!/usr/bin/env bash
# Builds cut-heights.src.svg: five raised cuts, each tied to an edge in the letters, at 200, 64, 32 and 24 px.
# Cut paths come from parts/cuts/cut-<v>.svg (solid word minus the slit, made in VectorCraft).
# Master units (250 px set): x-height 52.5, t crossbar 52.5 to 77.25, h counter top 75.75, r arm bottom 80.75, baseline 180.
set -e
BG="#F9F6ED"; INK="#2B1F1A"; GUIDE="#E0574F"
word() { # x baseline size variant top thickness guides(0|1)
  local s y; s=$(awk -v f=$3 'BEGIN{printf "%.5f", f/250}'); y=$(awk -v b=$2 -v f=$3 'BEGIN{printf "%.2f", b-180*f/250}')
  echo "<g transform=\"translate($1 $y) scale($s)\" fill=\"$INK\">"
  grep -o '<path d="[^"]*"' "parts/cuts/cut-$4.svg" | sed 's|$|/>|'
  echo "</g>"
  if [ "$7" = 1 ]; then
    local b; b=$(awk -v t=$5 -v h=$6 'BEGIN{print t+h}')
    echo "<g transform=\"translate($1 $y) scale($s)\"><path d=\"M-34 $5 H-10 M-34 $b H-10 M466 $5 H490 M466 $b H490\" stroke=\"$GUIDE\" stroke-width=\"2\" fill=\"none\"/></g>"
  fi
}
ROWS=("pick|83.2|16.06|Your pick from before|cut moved up, same thickness as now"
      "a|77.25|10|A  Under the crossbar, thin|top of the cut = bottom of the t crossbar, 10 units"
      "b|77.25|24.75|B  Mirror of the crossbar|starts under the crossbar, exactly as thick as it"
      "c|80.75|16.06|C  Under the r arm|top = bottom of the r arm, so the r keeps its whole arm"
      "d|80.75|24|D  Under the r arm, wide|same line, thicker, so the gap holds at 24 px"
      "e|75.75|8|E  Hairline at the h counter|top = top of the h counter, very thin")
{
echo "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1240\" height=\"1420\" viewBox=\"0 0 1240 1420\" font-family=\"Inter\">"
echo "<rect width=\"1240\" height=\"1420\" fill=\"$BG\"/>"
echo "<text x=\"40\" y=\"60\" font-size=\"28\" font-weight=\"600\" fill=\"$INK\">Raised cut, five heights and thicknesses</text>"
echo "<text x=\"40\" y=\"88\" font-size=\"15\" fill=\"#7A6A5C\">Red ticks mark the edges of the cut on the 200 px word.</text>"
for p in "420|200 px" "860|64 px" "1020|32 px" "1130|24 px"; do IFS="|" read -r x t <<<"$p"; echo "<text x=\"$x\" y=\"130\" font-size=\"14\" fill=\"#7A6A5C\">$t</text>"; done
y=290
for r in "${ROWS[@]}"; do
  IFS="|" read -r v top th title rule <<<"$r"
  echo "<text x=\"40\" y=\"$((y-90))\" font-size=\"18\" font-weight=\"600\" fill=\"$INK\">$title</text>"
  echo "<text x=\"40\" y=\"$((y-66))\" font-size=\"13\" fill=\"#7A6A5C\">$rule</text>"
  word 420 "$y" 200 "$v" "$top" "$th" 1
  word 860 "$y" 64 "$v" "$top" "$th" 0
  word 1020 "$y" 32 "$v" "$top" "$th" 0
  word 1130 "$y" 24 "$v" "$top" "$th" 0
  echo "<line x1=\"40\" y1=\"$((y+30))\" x2=\"1200\" y2=\"$((y+30))\" stroke=\"#E6DDCD\"/>"
  y=$((y+210))
done
echo "</svg>"
} > cut-heights.src.svg
echo built
