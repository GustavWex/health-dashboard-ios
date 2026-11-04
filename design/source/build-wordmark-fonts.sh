#!/usr/bin/env bash
# Builds wordmark-fonts.src.svg (1600 x 940): the cut wordmark in five fonts.
# Texts w1..w5 are outlined and cut in VectorCraft; the small lockups stay solid (no cut below 40 px).
set -e
. ./lib.sh
label() { echo "  <text x=\"$1\" y=\"$2\" font-size=\"18\" font-weight=\"600\" fill=\"#2B1F1A\">$3</text><text x=\"$1\" y=\"$(( $2 + 24 ))\" font-size=\"15\" fill=\"#7A6A5C\">$4</text>"; }
word() { # id x baseline size family weight tracking-em
  echo "  <text id=\"$1\" x=\"$2\" y=\"$3\" font-family=\"$5\" font-size=\"$4\" font-weight=\"$6\" letter-spacing=\"$(awk -v s=$4 -v t=$7 'BEGIN{printf "%.2f", s*t}')\" text-anchor=\"middle\" fill=\"#2B1F1A\">thru</text>"
}
mini() { # x baseline family weight tracking
  echo "  <image x=\"$1\" y=\"$(( $2 - 38 ))\" width=\"44\" height=\"44\" xlink:href=\"$A/AppIcon.png\" href=\"$A/AppIcon.png\"/>"
  echo "  <text x=\"$(( $1 + 55 ))\" y=\"$2\" font-family=\"$3\" font-size=\"40\" font-weight=\"$4\" letter-spacing=\"$(awk -v t=$5 'BEGIN{printf "%.2f", 40*t}')\" fill=\"#2B1F1A\">thru</text>"
}
cat > wordmark-fonts.src.svg <<EOF
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1600" height="940" viewBox="0 0 1600 940" font-family="Inter">
  <defs>
$(paper_defs 1600 940)
  </defs>
$(paper 1600 940 "1400 0 700" "1000 520 760" "100 960 620")
  <text x="80" y="76" font-size="34" font-weight="600" fill="#2B1F1A">thru wordmark, five fonts</text>
$(card f1 80 110 464 360 22)
$(card f2 568 110 464 360 22)
$(card f3 1056 110 464 360 22)
$(card f4 80 510 708 360 22)
$(card f5 812 510 708 360 22)
$(word w1 312 310 170 "Geist" 600 -0.045)
$(label 108 410 "1  Geist SemiBold" "Sharp and neutral, Vercel's typeface")
$(word w2 800 310 170 "Manrope" 700 -0.04)
$(label 596 410 "2  Manrope Bold" "Geometric, open and friendly")
$(word w3 1288 310 170 "Space Grotesk" 700 -0.04)
$(label 1084 410 "3  Space Grotesk Bold" "Quirky details in t and r")
$(word w4 434 720 190 "Instrument Sans" 600 -0.035)
$(label 108 810 "4  Instrument Sans SemiBold" "Tight and editorial")
$(mini 600 812 "Instrument Sans" 600 -0.035)
$(word w5 1166 720 190 "Fraunces" 600 -0.03)
$(label 840 810 "5  Fraunces SemiBold" "Soft, warm serif")
$(mini 1330 812 "Fraunces" 600 -0.03)
</svg>
EOF
echo built wordmark-fonts.src.svg
