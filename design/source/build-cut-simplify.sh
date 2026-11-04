#!/usr/bin/env bash
# Builds cut-simplify.src.svg: cut B (under the t crossbar, as thick as it) with the letters tidied so each piece stands alone.
set -e
BG="#F9F6ED"; INK="#2B1F1A"
word() { # x baseline size variant
  local s y; s=$(awk -v f=$3 'BEGIN{printf "%.5f", f/250}'); y=$(awk -v b=$2 -v f=$3 'BEGIN{printf "%.2f", b-180*f/250}')
  echo "<g transform=\"translate($1 $y) scale($s)\" fill=\"$INK\">"; grep -o '<path d="[^"]*"' "parts/cuts/cut-$4.svg" | sed 's|$|/>|'; echo "</g>"
}
ROWS=("b|B as it is|The h counter peeks above the cut, the r is held on by a thin neck, a sliver hangs under the r"
      "tidy|1  Tidy|h closed flat above the cut, thicker r neck, sliver gone"
      "flag|2  Flag r|h closed flat, the r top becomes one slab like a flag"
      "float|3  Floating arm|h closed flat, the r arm splits off as its own drop, like the u tops")
{
echo "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1400\" height=\"1330\" viewBox=\"0 0 1400 1330\" font-family=\"Inter\">"
echo "<rect width=\"1400\" height=\"1330\" fill=\"$BG\"/>"
echo "<text x=\"40\" y=\"60\" font-size=\"28\" font-weight=\"600\" fill=\"$INK\">Cut B, letters simplified</text>"
for p in "360|320 px" "1000|64 px" "1170|32 px" "1280|24 px"; do IFS="|" read -r x t <<<"$p"; echo "<text x=\"$x\" y=\"110\" font-size=\"14\" fill=\"#7A6A5C\">$t</text>"; done
y=370
for r in "${ROWS[@]}"; do
  IFS="|" read -r v title rule <<<"$r"
  echo "<text x=\"40\" y=\"$((y-150))\" font-size=\"18\" font-weight=\"600\" fill=\"$INK\">$title</text>"
  # wrap the note over two lines at the first comma
  l1=${rule%%,*}; l2=${rule#*,}; [ "$l1" = "$rule" ] && l2=""
  echo "<text x=\"40\" y=\"$((y-124))\" font-size=\"13\" fill=\"#7A6A5C\">$l1</text>"
  [ -n "$l2" ] && echo "<text x=\"40\" y=\"$((y-106))\" font-size=\"13\" fill=\"#7A6A5C\">${l2# }</text>"
  word 360 "$y" 320 "$v"; word 1000 "$y" 64 "$v"; word 1170 "$y" 32 "$v"; word 1280 "$y" 24 "$v"
  echo "<line x1=\"40\" y1=\"$((y+30))\" x2=\"1360\" y2=\"$((y+30))\" stroke=\"#E6DDCD\"/>"
  y=$((y+300))
done
echo "</svg>"
} > cut-simplify.src.svg
echo built
