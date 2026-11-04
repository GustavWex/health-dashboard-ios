#!/usr/bin/env bash
# Builds the salmon brand set into ../brand: wordmarks, the mood face mark, the lockup and the iOS app icon set.
# Brand colour: salmon #F07B62. Ink #2B1F1A, paper #F9F6ED, dark #1C1714.
set -e
OUT=../brand
INK="#2B1F1A"; PAPER="#F9F6ED"; SALMON="#F07B62"; DARK="#1C1714"
FROZEN_NOU='M22.5 30 H52.5 V60 H22.5 Z M0 60 H75 V90 H0 Z M90 0 H120 V90 H90 Z M90 120 H120 V180 H90 Z M165 120 H195 V180 H165 Z M120.758 90 A37.5 37.5 0 0 1 194.242 90 Z M210 60 H240 V90 H210 Z M240 90 A30 30 0 0 1 270 60 V90 Z M270 60 H285 V90 H270 Z M210 120 H240 V180 H210 Z'
NOU="$FROZEN_NOU $(cat parts/eased-t.txt)"
U="M300 60 H330 V90 H300 Z M375 60 H405 V90 H375 Z $(cat parts/u-constant.txt)"
svg() { echo "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$1\" height=\"$2\" viewBox=\"0 0 $1 $2\">"; }
word() { # file letters u-colour
  { svg 405 180; echo "<path fill=\"$2\" d=\"$NOU\"/><path fill=\"$3\" d=\"$U\"/></svg>"; } > "$OUT/$1"; }
# the face (the u) centred in a square of side S, face height = 56% of S
face() { # S colour
  local k ox oy; k=$(awk -v s=$1 'BEGIN{print s*0.56/120}')
  ox=$(awk -v s=$1 -v k=$k 'BEGIN{printf "%.3f", (s-105*k)/2-300*k}'); oy=$(awk -v s=$1 -v k=$k 'BEGIN{printf "%.3f", (s-120*k)/2-60*k}')
  echo "<g transform=\"translate($ox $oy) scale($k)\" fill=\"$2\"><path d=\"$U\"/></g>"; }
word thru-wordmark-ink.svg "$INK" "$INK"
word thru-wordmark-paper.svg "$PAPER" "$PAPER"
word thru-wordmark-salmon.svg "$INK" "$SALMON"
word thru-wordmark-salmon-on-dark.svg "$PAPER" "$SALMON"
# mark: rounded tile for docs and web (iOS rounds the app icon itself)
{ svg 1024 1024; echo "<rect width=\"1024\" height=\"1024\" rx=\"230.4\" fill=\"$SALMON\"/>"; face 1024 "$PAPER"; echo "</svg>"; } > "$OUT/thru-mark-salmon.svg"
{ svg 1024 1024; face 1024 "$INK"; echo "</svg>"; } > "$OUT/thru-face-ink.svg"
# lockup: mark (180 tall) + 45 gap + salmon wordmark (180 tall)
{ svg 630 180; echo "<rect width=\"180\" height=\"180\" rx=\"40.5\" fill=\"$SALMON\"/>"; face 180 "$PAPER"
  echo "<g transform=\"translate(225 0)\"><path fill=\"$INK\" d=\"$NOU\"/><path fill=\"$SALMON\" d=\"$U\"/></g></svg>"; } > "$OUT/thru-lockup.svg"
# iOS app icon set: full-bleed squares, no rounding or transparency (iOS applies the mask)
{ svg 1024 1024; echo "<rect width=\"1024\" height=\"1024\" fill=\"$SALMON\"/>"; face 1024 "$PAPER"; echo "</svg>"; } > "$OUT/AppIcon-1024.svg"
{ svg 1024 1024; echo "<rect width=\"1024\" height=\"1024\" fill=\"$DARK\"/>"; face 1024 "$SALMON"; echo "</svg>"; } > "$OUT/AppIcon-1024-dark.svg"
{ svg 1024 1024; echo "<rect width=\"1024\" height=\"1024\" fill=\"#000000\"/>"; face 1024 "#FFFFFF"; echo "</svg>"; } > "$OUT/AppIcon-1024-tinted.svg"
ls "$OUT"
