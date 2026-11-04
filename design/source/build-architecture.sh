#!/usr/bin/env bash
# Builds architecture.src.svg (1600 x 900). Run from docs/source.
set -e
. ./lib.sh

src() { # id y colour label
  card "$1" 80 "$2" 360 60
  echo "  <circle cx=\"108\" cy=\"$(($2 + 30))\" r=\"7\" fill=\"$3\"/>"
  echo "  <text x=\"128\" y=\"$(($2 + 37))\" font-size=\"20\" fill=\"#2B1F1A\">$4</text>"
}

cat > architecture.src.svg <<EOF
<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="900" viewBox="0 0 1600 900" font-family="Inter">
  <defs>
$(paper_defs 1600 900)
  </defs>
$(paper 1600 900 "1380 0 720" "1060 520 720" "100 920 620")

  <text x="80" y="112" font-size="46" font-weight="600" fill="#2B1F1A">How data flows</text>
  <text x="80" y="156" font-size="22" fill="#7A6A5C">Read only, computed on the device. Nothing leaves the phone unless you opt in.</text>

  <!-- connectors -->
  <g fill="none" stroke="#B9A894" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
    <path d="M440 292H456V436H440M440 364H456"/>
    <path d="M456 364H532"/>
    <path d="M770 364H820V470H862"/>
    <path d="M440 572H456V716H440M440 644H456"/>
    <path d="M456 644H820V570H862"/>
    <path d="M1230 400H1286M1230 520H1286M1230 640H1286"/>
  </g>
  <g fill="#B9A894">
    <path d="M540 364l-10 -6v12z"/>
    <path d="M870 470l-10 -6v12z"/>
    <path d="M870 570l-10 -6v12z"/>
    <path d="M1294 400l-10 -6v12z"/>
    <path d="M1294 520l-10 -6v12z"/>
    <path d="M1294 640l-10 -6v12z"/>
  </g>

  <!-- sources -->
  <text x="80" y="246" font-size="16" font-weight="600" fill="#7A6A5C">Through Apple Health</text>
$(src watch 262 "#21A8BD" "Apple Watch")
$(src scale 334 "#F29433" "Any smart scale app")
$(src food 406 "#E3598F" "Any food logging app")
  <text x="80" y="526" font-size="16" font-weight="600" fill="#7A6A5C">Direct</text>
$(src withings 542 "#F29433" "Withings API")
$(src scalecsv 614 "#F29433" "Scale app CSV")
$(src lifting 686 "#2978F2" "Strong or Hevy CSV")

  <!-- Apple Health -->
$(card health 540 326 230 76)
  <path d="M578 375c-9-6-15-11-15-18 0-4.5 3.5-8 8-8 3.2 0 5.5 1.8 7 4.3 1.5-2.5 3.8-4.3 7-4.3 4.5 0 8 3.5 8 8 0 7-6 12-15 18z" fill="none" stroke="#2B1F1A" stroke-width="2" stroke-linejoin="round"/>
  <text x="606" y="372" font-size="20" font-weight="600" fill="#2B1F1A">Apple Health</text>

  <!-- HealthCore, the one accent -->
$(card core 870 330 360 352 22)
  <rect x="870" y="330" width="360" height="352" rx="22" fill="none" stroke="#E8543D" stroke-opacity="0.55" stroke-width="1.5"/>
  <text x="902" y="386" font-size="30" font-weight="600" fill="#E8543D">HealthCore</text>
  <text x="902" y="414" font-size="16" fill="#7A6A5C">Swift package, Foundation only, 139 tests</text>
  <path d="M902 438H1198" stroke="#E6DDCD" stroke-width="1.5"/>
  <g font-size="19" fill="#2B1F1A">
    <text x="902" y="474">Recovery and zones</text>
    <text x="902" y="504">Sleep score</text>
    <text x="902" y="534">Strain and load</text>
    <text x="902" y="564">Diet quality</text>
    <text x="902" y="594">Insights with FDR</text>
    <text x="902" y="624">Bayesian forecast</text>
    <text x="902" y="654">Shapley parts</text>
  </g>

  <!-- outputs -->
$(card iphone 1300 362 224 76)
$(card watchout 1300 482 224 76)
$(card widgets 1300 602 224 76)
  <g font-size="20" font-weight="600" fill="#2B1F1A">
    <text x="1376" y="407">iPhone app</text>
    <text x="1376" y="527">Apple Watch</text>
    <text x="1376" y="647">Widgets</text>
  </g>
  <g fill="none" stroke="#2B1F1A" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
    <rect x="1332" y="382" width="22" height="36" rx="6"/>
    <path d="M1339 388h8"/>
    <path d="M1335 496h16M1335 544h16"/>
    <rect x="1328" y="502" width="30" height="36" rx="9"/>
    <rect x="1328" y="624" width="14" height="14" rx="4"/>
    <rect x="1346" y="624" width="14" height="14" rx="4"/>
    <rect x="1328" y="642" width="32" height="14" rx="4"/>
  </g>
</svg>
EOF
echo built architecture.src.svg
