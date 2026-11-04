#!/usr/bin/env bash
# Fills the wordmark parts into the mockup pages: today-mockup.src.html -> today-mockup.html, screens-mockup.src.html -> screens-mockup.html.
# Run from design/lab: bash build-mockups.sh
set -e
T=$(tr -d '\r\n' < ../source/parts/eased-t.txt)
U=$(tr -d '\r\n' < ../source/parts/u-constant.txt)
for f in today-mockup screens-mockup; do
  awk -v t="$T" -v u="$U" '{gsub(/__TFOOT__/, t); gsub(/__UBOWL__/, u); print}' "$f.src.html" > "$f.html"
done
echo built
