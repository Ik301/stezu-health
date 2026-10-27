# UI/UX walkthrough

Four interactive walkthroughs in the Walkthrough group of Components: WalkHome, WalkData, WalkFood and WalkWorkout. Each is the clickable phone with a panel that explains every screen; the toolbar jumps between the flow's screens and switches Light, Dark and System. All numbers are synthetic.

## Decisions taken (2026-10-27)

- **Data card leads with sleep.** Last night's time asleep is the Home number; weight is a small weekly figure in the detail row. This is a second daily number beside today's food, which DESIGN.md's display rule does not allow yet: record it as a decision in the engineering system before building.
- **No buttons inside Home cards.** The whole card is the control; Food opens the camera.
- **Light and dark follow the phone,** and sparklines are on in This week.
- **Sleep window first** on the Sleep screen, fixed at 14 nights, no range switch. Nights are named by the day you woke up.
- **No scores, rings, targets or red/green** anywhere (D-032). Strength progress is shown as history (best set against the last session of the same template), never as a suggestion.

## Flows and taps from Home

| Flow | Screens | Taps |
| --- | --- | --- |
| Glance | Home | 0 |
| How was my week | This week | 1 |
| Why did I sleep like that | This week, Sleep, a night | 2 to 3 |
| What did that day look like | Sleep, "as a day", previous/next | 3, then 1 per day |
| Log a meal | Food card, shutter, (servings), Log | 3 |
| Log a set | Workout card, Start, Log | 3, then 1 per set |
| Finish and review | Finish | 1 |

## 1. Home
Three cards, each in three rows: header, a centred number, a detail row. Data: sleep with 7-night bars, usual and weekly weight. Food: today's kcal range, protein and meal count. Workout: sessions with Monday to Sunday dots, the next template and working sets.

## 2. Data
- This week: cards with headers (Body and activity, Food and training, Recovery with one "context only" tag, Places). Every row has a sparkline and a chevron; missing days are dashed slots, rest days a baseline stub.
- Sleep: number, usual (own median), window chart with labelled usual lines, stages of the selected night (stage times on the lanes, wake-ups in the warm hue, "estimated by the strap"), one overnight line (heart rate, breathing, HRV), link to the day.
- Day: summary of the day, then a timeline where empty hours fold to a thin band; places by name on the left, sleep (with a stage stripe), weigh-in, meals and the workout on the right; previous and next day arrows.

## 3. Food
- Camera: today's running total on a scrim, Search, History, shutter, Photo/Barcode.
- Match sheet: totals in the data colours, items with half-step servings (totals update), Add item, Log at the bottom.
- Today: energy and protein ranges, the meals with photo and ranges, this week as low-to-high bands with a dashed slot for the missing day.

## 4. Workout
- Workout: the next template as the black card with Start, this week's sessions and sets with the same day dots as Home, other templates with when each was last done, Import program.
- Logger: steppers, Log fixed at the bottom of the black card, a 90 s rest inside the card with -15, +15 and Skip, the next set as a dashed row with last time's numbers, progress across exercises. The area nav is hidden while logging.
- Summary: duration, working sets, volume, In Health; each exercise's sets and its best set against the last session of the template.

## Not drawn yet
Barcode, Search results, meal editing, Swap exercise, workout History list, Settings. They are tap-through notes in the walkthroughs.
