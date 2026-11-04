# Shared pieces for the thru README visuals. Source this from a build script.

A=../assets

# Watch defs (gradients and screen clip) from a watch part.
watch_defs() { sed -n '/<defs>/,/<\/defs>/p' parts/watch-day.svg | sed '1d;$d'; }

# Watch body from parts/$1.svg, ids prefixed with $2, asset paths fixed for docs/source.
watch_body() {
  sed -n '/<g transform="translate(20 214)">/,/^  <\/g>$/p' "parts/$1.svg" | sed '1d;$d' |
    sed "s#\.\./\.\./assets#$A#g; s#id=\"band-top\"#id=\"$2-band-top\"#; s#id=\"band-bot\"#id=\"$2-band-bot\"#; s#id=\"watch-shadow\"#id=\"$2-shadow\"#; s#url(\#wScreen)#url(\#wScreen-$2)#g"
}

# Screen clip per watch, so several watches can share one file.
watch_clip() { echo "    <clipPath id=\"wScreen-$1\"><rect x=\"12\" y=\"12\" width=\"208\" height=\"248\" rx=\"48\"/></clipPath>"; }

# Paper background with the design system's three soft glows, clipped to the card.
# $1 width, $2 height, then glow centres: red, orange, amber as "cx cy r".
paper() {
  local w=$1 h=$2
  read -r rx ry rr <<<"$3"; read -r ox oy orr <<<"$4"; read -r ax ay ar <<<"$5"
  cat <<EOF
  <g clip-path="url(#frame)">
    <rect width="$w" height="$h" fill="#F9F6ED"/>
    <circle cx="$rx" cy="$ry" r="$rr" fill="url(#gRed)"/>
    <circle cx="$ox" cy="$oy" r="$orr" fill="url(#gOrange)"/>
    <circle cx="$ax" cy="$ay" r="$ar" fill="url(#gAmber)"/>
  </g>
EOF
}

paper_defs() {
  cat <<EOF
    <clipPath id="frame"><rect width="$1" height="$2" rx="28"/></clipPath>
    <radialGradient id="gRed" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#E02E3D" stop-opacity="0.09"/><stop offset="1" stop-color="#E02E3D" stop-opacity="0"/></radialGradient>
    <radialGradient id="gOrange" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#F78033" stop-opacity="0.11"/><stop offset="1" stop-color="#F78033" stop-opacity="0"/></radialGradient>
    <radialGradient id="gAmber" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#FCC254" stop-opacity="0.16"/><stop offset="1" stop-color="#FCC254" stop-opacity="0"/></radialGradient>
EOF
}

# Glass card: 38% white wash and a white hairline. The soft shadow is added in VectorCraft
# (stylize.dropShadow on every object named card-*), since the SVG importer has no blur filter.
card() { echo "  <rect id=\"card-$1\" x=\"$2\" y=\"$3\" width=\"$4\" height=\"$5\" rx=\"${6:-18}\" fill=\"#FFFFFF\" fill-opacity=\"0.42\" stroke=\"#FFFFFF\" stroke-opacity=\"0.95\" stroke-width=\"1.5\"/>"; }

# The cut wordmark (Instrument Sans SemiBold, cut) as vector paths, baseline at y=180 of a 250 px set. $1 x, $2 baseline, $3 font size it replaces, $4 colour.
wordmark() {
  local s; s=$(awk -v f=$3 'BEGIN{printf "%.5f", f/250}')
  local y; y=$(awk -v b=$2 -v f=$3 'BEGIN{printf "%.2f", b - 180*f/250}')
  echo "  <g transform=\"translate($1 $y) scale($s)\" fill=\"${4:-#2B1F1A}\">"
  sed 's/fill="[^"]*"//g' parts/wordmark-paths.svg
  echo "  </g>"
}

# Wordmark variant: $1 x, $2 baseline, $3 size, $4 colour, $5 paths file, $6 extra transform (e.g. skewX(-12)).
wordmark_v() {
  local s; s=$(awk -v f=$3 'BEGIN{printf "%.5f", f/250}')
  local y; y=$(awk -v b=$2 -v f=$3 'BEGIN{printf "%.2f", b - 180*f/250}')
  local sk=""; [ -n "$6" ] && sk=" translate(38.25 0) $6"
  echo "  <g transform=\"translate($1 $y) scale($s)$sk\" fill=\"$4\">"
  sed 's/fill="[^"]*"//g' "$5"
  echo "  </g>"
}
# Plain (uncut) wordmark text for sizes under 40 px.
wordmark_solid() { echo "  <text x=\"$1\" y=\"$2\" font-family=\"Instrument Sans\" font-size=\"$3\" font-weight=\"600\" letter-spacing=\"$(awk -v f=$3 'BEGIN{printf "%.2f", -f*0.035}')\" fill=\"${4:-#2B1F1A}\">thru</text>"; }
