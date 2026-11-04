#!/usr/bin/env bash
# Builds logo-lockup.src.svg: the app icon (160) with the cut wordmark, transparent background, for docs/logo.
set -e
. ./lib.sh
cat > logo-lockup.src.svg <<EOF
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="460" height="160" viewBox="0 0 460 160">
  <defs><clipPath id="ic"><rect width="160" height="160" rx="36"/></clipPath></defs>
  <image clip-path="url(#ic)" width="160" height="160" xlink:href="$A/AppIcon.png" href="$A/AppIcon.png"/>
$(wordmark 200 129.5 137.6)
</svg>
EOF
echo built logo-lockup.src.svg
