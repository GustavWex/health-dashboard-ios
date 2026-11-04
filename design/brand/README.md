# thru brand files

Built by `design/source/build-brand.sh` from the master wordmark. Brand colour: salmon `#F07B62`.
Ink `#2B1F1A`, paper `#F9F6ED`, dark `#1C1714`.

| File | Use |
| --- | --- |
| `AppIcon-1024.png` / `.svg` | iOS app icon, default (light): paper face on salmon |
| `AppIcon-1024-dark.png` / `.svg` | iOS app icon, dark appearance: salmon face on dark |
| `AppIcon-1024-tinted.png` / `.svg` | iOS app icon, tinted appearance: white face on black, iOS adds the tint |
| `thru-mark-salmon.png` / `.svg` | The mark with rounded corners, for the web, docs and social images |
| `thru-face-ink.png` / `.svg` | The face alone in ink, transparent |
| `thru-lockup.png` / `.svg` | Mark and wordmark side by side |
| `thru-wordmark-salmon.png` / `.svg` | Wordmark, ink letters with a salmon u, for light backgrounds |
| `thru-wordmark-salmon-on-dark.png` / `.svg` | Wordmark, paper letters with a salmon u, for dark backgrounds |
| `thru-wordmark-ink.png` / `.svg` | Wordmark, all ink |
| `thru-wordmark-paper.png` / `.svg` | Wordmark, all paper, for dark backgrounds |

The app icons are full-bleed 1024 x 1024 squares with no transparency and no rounded corners, as the App Store
requires; iOS applies the rounded mask. The other PNGs have transparent backgrounds. Wordmark PNGs are 1620 x 720
(4x the 405 x 180 master).

To use the icons in the app, put the three 1024 PNGs in `HealthDashboard/Assets.xcassets/AppIcon.appiconset` and
list them in its `Contents.json` with the `luminosity` appearances `dark` and `tinted`.
