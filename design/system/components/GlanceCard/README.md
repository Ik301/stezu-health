# GlanceCard

A Home card in three rows: the area name with its time frame, one number centred in the middle with a small picture beside it, and a detail row; the whole card is the button.

## Use
- Three cards share Home's height evenly: Data, Food, Workout. Never scroll Home.
- Header: area name in 15 medium `ink`, time frame ("Last night", "Today", "This week") in `t-label`/`muted`.
- Middle: the number in `t-big`, shrinking to fit the card width (a long range like "1,080–1,440" scales down instead of overflowing). Units small beside it. A picture on the right when it adds the shape of the week: 7 sleep bars on Data, day dots on Workout. Food has none; its range is wide enough.
- Detail row: one fact left, one right, 13 px `muted` with the value in `ink`.
- The card is the only control. No buttons inside it: tapping Food opens the camera, Data opens This week, Workout opens the Workout screen.
- One card is `is-invert` (time of day; state first when a workout is in progress).

## Content per card (decided 2026-10-27)
- Data: last night's time asleep, 7-night bars, "Usual 6h 9m" and the week's trend weight. Weight is small on purpose: it is not a day-to-day number.
- Food: today's kcal range; protein range and meal count in the detail row.
- Workout: sessions this week with the Monday to Sunday dots (filled = trained, outlined = today); next template and working sets in the detail row.

## Don't
- Put a button, target, ring or score in a card (D-032).
- Show 0 for a missing value: "--".
