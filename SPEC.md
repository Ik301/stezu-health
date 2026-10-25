# Spec

v1 scope: D-032 to D-035 in DECISIONS.md override this file where they differ (tracking only, no targets; Food has text search, barcode and an editable item list). The v1 work list is the stories in features.json.

## Goal

One iPhone app for the health data that has to be entered by hand: meals, gym sets and weigh-ins. Everything else is read from Apple Health. Logging must cost fewer taps than skipping it, and the app shows only numbers that are worth acting on each week.

## Screens

- Home: three tall cards (Data, Food, Workout). Each card has a label, a subtitle and a big number. Time of day decides which card is the inverted "log this now" card. Today's totals are visible with 0 taps.
- Data: trend weight and its weekly rate, the one-tap weigh-in, and HRV and sleep as context only.
- Food: a camera shutter, then one Log tap. There is no keyboard, ever. The screen shows today's intake against the target and the weekly protein average.
- Workout: the current exercise with the last session's numbers, one tap to log a set, a rest timer, and the double-progression suggestion for next time.
- Sub-screens share a bottom nav of three circles (Data, Food, Workout).

## Display rules

- Weekly numbers by default. The only daily number is today's intake against the target.
- No composite daily score.
- HRV and sleep are context only. No rule acts on them.
- Absent is not zero. Missing values show "--", never 0.
- Every derived value carries a confidence: a level and the reason for it, such as the number of weigh-ins behind a trend.

## Data sources

- Apple Health through HealthKit: body mass (read and write), plus whatever the wearable writes (heart rate, HRV, sleep, workouts) as context. All HealthKit access sits behind a HealthStore protocol in StezuCore, with a fake for tests.
- Meal photos: estimated through an endpoint on the owner's VM with a per-device token. No model API key ships in the app. Estimates are ranges (low and high) for energy and protein.
- Princeton dining menus (FoodPro), served through a VM endpoint. Later.
- Barcodes. Later.

## Non-goals

- Manual food entry of any kind.
- A daily composite score.
- CloudKit, push notifications or anything else that needs a paid Apple developer account.
- Health data in prompts or anywhere in this repo. Tests and fixtures use synthetic numbers.

## L1 weekly energy-balance rule

Every parameter below is a default or a convention. All of them are configurable, and none is a personal number. Weights are in pounds and energy is in kcal.

### Trend weight

- An exponentially weighted moving average with alpha of about 0.1 per day.
- Weigh-ins are irregular: they happen on gym days only, about 5 a week. For a gap of d days since the previous weigh-in, the new weigh-in gets weight 1 - (1 - alpha)^d, so a longer gap moves the trend further.
- The first weigh-in seeds the trend. Days without a weigh-in are missing, not zero, and do not update the trend.

### Expenditure estimate

- Window: the last 21 days.
- Intake: the mean logged intake over the window, excluding partial days. A day is partial when its logged intake is under 50% of that week's typical intake (the median of that week's logged days).
- Expenditure = mean intake - (trend change over the window x 3500 kcal/lb) / 21.
- With too little data the result is "insufficient data", never 0.

### Weekly target rule

- Needs at least 4 weigh-ins in the current week and at least 21 days of data. Otherwise it returns "insufficient data" and makes no change.
- Target rate: configurable, default 0.35 lb/week of gain, within a band of 0.25 to 0.5 lb/week.
- Trend rate: the trend change over the last 3 weeks, divided by 3.
- If the trend rate is more than 0.15 lb/week under the target rate, raise the kcal target by a configurable step of 100 to 150 kcal.
- If the trend rate is more than 0.25 lb/week over the target rate, lower the kcal target by 100 kcal.
- Otherwise make no change. At most one change per week.
- The result carries a confidence and the reason for the decision.

### Protein floor flag

- Each meal's protein estimate is a range, and the flag uses the low end of it.
- Flag when the 3-day rolling mean of daily protein is under a configurable floor in grams per day. The floor is set on the device; the repo ships no personal value.
- With fewer than 3 days of logged food the result is "insufficient data", not a flag.
