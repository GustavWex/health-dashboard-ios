# thru

***Intelligent*** **recovery, sleep and strain you can see right through.**

A personal, Whoop-style health app for iPhone and Apple Watch. It reads Apple Watch, smart scale, food logging and lifting data and turns it into recovery, sleep, strain, nutrition and body composition scores, with explanations for every number. Everything is computed on the device: no server and no accounts.

```
Apple Watch ─────────────┐
Any smart scale app ─────┼──> Apple Health ──> HealthKit (read only) ──┐
Any food logging app ────┘                                             │
Withings API (body composition) ───────────────────────────────────────┼──> this app ──> watch app, widgets
Scale app CSV (Renpho, Eufy, Garmin, Fitbit, Zepp, Withings) ──────────┤
Strong or Hevy CSV (sets, reps, weights) ──────────────────────────────┘
```

## Highlights
- **Recovery, sleep and strain scores** from overnight HRV, resting heart rate, breathing rate and sleep, scored against your own 60-day baseline, with personal zones and safety gates.
- **Explainable by design.** Today's recovery breaks down into exact Shapley values (the idea behind SHAP), with what-if lines and plain-language reasons.
- **Bayesian forecast.** A conjugate Normal regression learns how workouts move your recovery over the next days, shown only where it beats a naive baseline in a rolling backtest.
- **Insights with honest statistics.** Habits are tested against next-morning outcomes with autocorrelation-corrected sample sizes and Benjamini-Hochberg false discovery control.
- **Nutrition and body.** Diet quality over all 33 Apple Health nutrients, adaptive energy expenditure from intake and trend weight, and body composition from the Withings API or any scale app's CSV export, matched by column name rather than brand.
- **Strength log.** Strong and Hevy exports, with volume load, estimated 1RM progress and each session matched to its watch workout.
- **Apple Watch app.** Complications, a movement-based smart alarm, a smart nap that counts from sleep onset, and a desk mode that taps you when you start nodding off.
- **Every formula has a citation and a golden-vector test.** 139 tests in the `HealthCore` package.

## Tech
SwiftUI, Swift Charts, SwiftData, HealthKit, WidgetKit, WatchKit and WatchConnectivity, App Intents, Core Motion, Swift 6 concurrency. iOS 17 and watchOS 10. The project is generated with XcodeGen.

| Folder | What's in it |
|---|---|
| `HealthCore/` | Swift package with every engine and formula, Foundation only, fully tested |
| `HealthDashboard/` | The iPhone app |
| `HealthWidget/` | Home and lock screen widgets |
| `HealthWatch/`, `HealthWatchWidget/` | The watch app and its complications |
| `Shared/` | Code shared by the app, widgets and watch |

## Setup

### 1. Get the data into Apple Health
- **Withings:** in the Withings app, turn on Apple Health sync and allow weight, body fat and lean mass.
- **Apple Watch:** set up Sleep in the Health app (sleep schedule plus "Track Sleep with Apple Watch") and wear the watch at night. Overnight HRV, resting HR, sleep stages and wrist temperature all depend on this.
- **Food (optional):** any logging app that writes calories and protein to Health.

### 2. Generate the Xcode project
The project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen), so the `.xcodeproj` is not in git.

```
~/.local/bin/xcodegen generate
open HealthDashboard.xcodeproj
```

HealthKit entitlement, the Health usage text and iOS 17 deployment are already set. To build it yourself, change `bundleIdPrefix`, the App Group and `DEVELOPMENT_TEAM` in `project.yml` to your own. Run `xcodegen generate` again after adding or removing files.

### 3. Run it on your iPhone
HealthKit doesn't work in the Simulator. Plug in the iPhone, select it as the run destination and press Run. The first time, go to Settings, General, VPN & Device Management and trust your developer certificate.

A free Apple ID works for running on your own phone, but the app expires after 7 days and you re-run it from Xcode. The paid Developer Program (99 USD per year) makes builds last a year and unlocks TestFlight.

### 4. Tests and the Simulator
All scores and formulas live in the `HealthCore` package and are checked against fixed expected values:

```
cd HealthCore && swift test
```

The Simulator has no Health data, so debug builds there show 180 days of made-up data instead, plus a made-up Strong log.

## How the numbers work

**Recovery (0 to 100).** Log transformed HRV, resting HR, breathing rate and sleep duration are each compared with your previous 60 days as z-scores, weighted 55 / 20 / 10 / 15, then mapped through the normal CDF. HRV and breathing rate only count readings taken while you slept. Missing inputs get their weight redistributed. Needs 14 nights before it shows a score. Weights from GenieMax.

**Zones.** Your own 25th and 75th percentile over the last 30 days decide Recover / Moderate / Push, so your zones fit your baseline instead of fixed cutoffs. Inspired by Omnio.

**Safety gates.** These cap the zone regardless of the score: HRV more than 1 or 2 SD below baseline, your 7-day HRV average below its normal range, resting HR more than 1 or 2 SD above, sleep in your shortest 10% of nights, wrist temperature 0.5 °C above baseline.

**Overnight check.** HRV, resting HR, breathing rate, wrist temperature, blood oxygen and sleep, each against your own range over the last 60 days. It says "unusual for you", nothing more, and sends no notifications.

**Sleep.** Naps are shown separately and never added to your night. Awakenings count wake bouts of 2 minutes or more, with bouts under 2 minutes apart merged (calibrated against Withings on a real night), so brief stirs don't make the night look twitchy. Watch sleep stages are rough estimates, so the app leans on total sleep, awakenings and consistency.

**Sleep score (0 to 100).** Our own score with the same parts as the Withings one: duration against your sleep need (30%), wake time after falling asleep, full marks up to 30 minutes (20%), regularity as the Sleep Regularity Index over 7 days (15%), HRV (15%) and heart rate (10%) while asleep against your last 60 nights, and deep plus REM share against your own usual share (10%, lowest because stage estimates are rough). Tap the Sleep card for the details, a stage chart and the night's heart rate, HRV and breathing.

**Strain (0 to 21).** From workout heart rate: each minute counts more the closer you are to your max (Banister TRIMP), using your resting heart rate and a max from your age or your highest recorded workout heart rate. Scaled so your usual training day lands at 10.5. Today's target comes from your recovery: around 10.5 on an average day, higher when recovered, lower when not.

**Fitness, fatigue and form.** Your daily strain load averaged over 42 days (fitness) and 7 days (fatigue). Form is fitness minus fatigue: positive means fresher than your recent training, negative means carrying fatigue.

**Effort load.** Rate a workout's effort on your Apple Watch afterwards and the app multiplies it by the minutes (session RPE, Foster et al. 2001). Heart rate undercounts heavy lifting, so this is the fairer load for strength sessions.

**Strength log.** Import a Strong or Hevy export (Settings, Strength log); the format is detected from the header. Volume load is weight × reps over working sets (Haff 2010). Estimated 1RM is the Epley formula, weight × (1 + reps / 30), on the best set of each session up to 10 reps (LeSuer et al. 1997). Each workout's detail shows the sets logged during it.

**Training load.** Acute:chronic ratio of active energy (7 vs 28 days), shown as load against your recent normal, not as injury risk. Your training rhythm is detected from strength workouts over the last 8 weeks: fixed weekdays, or an interval like every other day. Trends shows this week's activities against your usual week.

**Body.** Uses the first weigh-in of each day. A moving average smooths it, and the 28-day slope gives your rate in kg per week.

**Nutrition.** Your daily burn is estimated the MacroFactor way: average logged intake minus the change in trend weight over 28 days, at 7700 kcal per kg (Wishnofsky 1958). That figure is an approximation, and lean gain stores less energy per kg (Hall 2008). It needs 14 logged days and 8 weigh-ins in 4 weeks; until then the watch's basal plus active energy stands in. From the burn and your weight goal in Settings the app suggests a daily intake. It also shows protein per kg, the macro split, fiber and sugar (Health has no added-sugar type), and when your last meal lands before sleep, from the times your food app logs. Cronometer logs by the hour, so each meal is placed mid-hour. Details on the Nutrition card opens an overview by week, month or 3 months.

**Journal.** Tag a day, and after 3 or more tagged days the app shows how your next-morning recovery differs from untagged days.

**Insights.** Every habit (bedtime, sleep, calories, macros, last meal to sleep, steps, strain, workouts, lifting volume, journal tags) is compared with your recovery, HRV, resting heart rate and sleep efficiency the next 1 to 3 mornings. Weekday patterns are removed first, and nutrition is also checked against that night's sleep. Because days aren't independent, the sample size is shrunk for autocorrelation (Bretherton et al. 1999), and because many pairs are tested, only those passing a 10% false discovery rate (Benjamini and Hochberg 1995) are shown. Each finding reads like "Bedtime before 23:10: recovery 71 vs 58". Patterns, not proof of cause. The tab also compares this week with your usual 4 weeks.

**Forecast and recovery curves.** A small Bayesian model learns how much of a good or bad morning carries into the next and how a workout 1 to 4 days ago moves your recovery and HRV. Each coefficient starts from a cautious prior (no effect, fading with time) and is updated by your data; the conjugate Normal prior gives the update in closed form (Bishop 2006). Today shows the next mornings for your usual rhythm and for rest, but only for days where the model beat "same as today" over the last 30 mornings, refit each time. Insights shows the curve after a strength workout with its uncertainty, and "How the model works" lists the fitted values and the backtest.

**Trends and widget.** One picker sets the range for every chart (7 days to all time; past 4 months charts show weekly averages). Touch a chart to read the exact value of a day. Add the Recovery widget to your home or lock screen; it shows the score from the app's last refresh and clears at midnight until you open the app again.

**Export and Ask your data.** Settings, Your data, Export data makes a CSV and JSON file with one row per day to share or analyze elsewhere. Ask your data (the speech bubble on Trends) sends your question plus a summary of your data to a provider you pick in Settings, Assistant: Google Gemini, Groq, Ollama on your own Mac, or any OpenAI-compatible service. It is off until you allow it, and you can read exactly what is sent first. Free tiers may use what you send to improve their models.

**Withings body composition.** Apple Health has no place for muscle mass, body water, bone mass or visceral fat, so the app can read them straight from Withings: Settings, Withings, Connect. It needs your own Withings developer app; put its client ID and secret in `data/withings.env` and run `scripts/withings-secrets.sh` before building. Under Withings' current terms the API may require Withings+.

**Other smart scales.** Any scale whose app writes to Apple Health gives weight, body fat and lean mass with no setup. For the rest, export a CSV from the scale's app and import it in Settings, Other smart scales. Columns are matched by name ("Weight (kg)", "Body Fat(%)", "Hydration", "Visceral Fat"), units are read from headers or cells, pounds are converted, and percentages of water or muscle become kg using that weigh-in's weight. Imports only fill days Apple Health and Withings left empty.

**Balance.** The big blob on Today is your balance: last night's sleep score (45%), yesterday's food (30%) and yesterday's strain against the target your recovery set (25%), each 0 to 100. Sleep weighs most because short sleep undermines muscle building and body composition (Nedeltcheva et al. 2010; Lamon et al. 2021). Food combines diet quality (nutrient density adapted from the Nutrient Rich Foods index), protein against your target and calories against the intake your weight goal needs. Rest days don't count against you. Tap it to split it into its parts.

**Why today's score.** Today lists the inputs that moved your score most, compared with your own normal. "How today's score was made" shows a breakdown from 50 (a morning where everything is at your normal) to today's score. Because the score is a simple weighted formula, the breakdown is exact: Shapley values, the idea behind SHAP, computed over every order the inputs could be added in. What-if lines show the score if one input had been at your normal.

**How you feel.** Pick 1 to 5 on Today each morning and tap Save; the question then goes away for the day. After 14 mornings the Recovery page shows how well the score agrees with how you feel (rank correlation with a range), and Insights treats your rating as one more outcome to explain.

**Bedroom air.** Ready for the room monitor (CO2, temperature, humidity, light). Info, Bedroom imports its CSV exports and shows each night's CO2 curve, CO2 at wake-up, minutes over 2,000 ppm, humidity, and the room's air change rate fitted from how fast CO2 falls after you get up. Bedroom readings also show on each night in Sleep and are tested as habits in Insights.

## Caveats
- Apple Watch HRV is SDNN, sampled a few times per night, not continuous RMSSD like Whoop. Trust trends over single days.
- Bioimpedance body fat and lean mass are noisy. Read them over 4 to 8 weeks, not week to week.
- Active energy undercounts heavy lifting, so the load ratio is a rough proxy for strength work.
- Watch energy estimates can be off by 10 to 20 percent, so read the nutrition balance as a direction, not an exact number.
- Wellness tool, not medical advice.

## Apple Watch
The watch app shows the day's status, sleep and strain from the phone, with complications for each. It also has a smart alarm that wakes you at the first sign of light sleep in a window before your wake time, a smart nap that counts from when you fall asleep and caps at 30 minutes, and a desk mode that taps you to stand up when your wrist goes still and your heart rate drops. The phone's Start desk mode shortcut can start desk mode from a Shortcuts automation.

## Roadmap ideas
1. Your own food logger using the Frida database, writing to Apple Health.
2. An own set logger to replace the Strong CSV import.
3. Bayesian personal recovery curves per muscle group.
4. Live bedroom air readings from the room monitor.

## License
MIT, see `LICENSE`.
