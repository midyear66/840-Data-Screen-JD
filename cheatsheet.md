# Judgment Day Pacing Cheatsheet

10 trails · ~70 mi · 24 hr · trail 1 opens 6:00 AM · finish by 6:00 AM next day

---

## Tiles

| Tile | What it shows | Warn / Alert |
|------|---------------|---------------|
| **W** | Power (3-second smoothed) | ≥ 120w warn · ≥ 135w alert |
| **NP** | Coggan Normalized Power (30s rolling) | ≥ 128w warn · ≥ 145w alert |
| **BPM** | Heart rate | ≥ 138 warn · ≥ 147 alert |
| **MI** | Distance — target ~70 total | — |
| **W'bal** | % match remaining (anaerobic) | < 40% warn · < 20% flash |
| **EF** | % HR-rise vs morning baseline (10-min rolling) | `--` until baseline locks + 5 min rolling fill |

---

## Row 4 reading guide

**W' Bal — "can I push *this* climb?"** (seconds–minutes)

- 70–100% — send freely
- 40–70% — pick spots, no junk surges
- <40% — soft-pedal, let it recover

**EF Drift — "how cooked am I overall?"** (hours)

- 0–3% — well-paced, sustainable
- 3–7% — warming, monitor
- 7–12% — cooked: eat, drink, cool
- 12–18% — dial back hard
- 18%+ — pull-out territory

---

## Mode guide — push / steady / recover / rest / stop

**Two roles for the six tiles:**

- **Row 4 (W' Bal + EF Drift) = the *diagnosis*.** These two tiles tell you *which mode* you're in. They are state — you read them, you don't aim at them. W' Bal recovers on its own when you ease up; EF Drift climbs slowly with cumulative fatigue. They answer "where am I right now?"
- **Rows 1–3 (W, NP, BPM) = the *prescription*.** These three tiles tell you *how to ride* inside that mode. They are targets — once you know your mode from row 4, you keep these three numbers under the ceilings in the table below. They answer "what should I do for the next 5 minutes?"

So the workflow is: **glance at row 4 → look up the mode → ride to the row 1–3 ceilings for that mode.** When row 4 changes (W' Bal drops a band, or EF Drift crosses a threshold), you've shifted modes — re-read the table and adopt the new ceilings.

| Mode | When (W' Bal / EF Drift) | Target ceilings (W / NP / BPM) | On the trail | Between trails | Fuel & water (per hour) |
|------|--------------------------|--------------------------------|--------------|----------------|--------------------------|
| **PUSH** — green light | 70–100% / 0–3% **or** 70–100% / 3–7% | W ≤ 120 avg · NP ≤ 128 · BPM ≤ 138 sustained · climbs to 170 W / 145 BPM OK briefly | Send the climbs. Hit your power numbers. Stay in the saddle on punchy ups. | Normal turnaround, ~15 min. Pee, refill, eat, go. | 60 g carbs · 500 mL water · 1 pinch salt |
| **STEADY** — pace it | 70–100% / 7–12% **or** 40–70% / 0–3% **or** 40–70% / 3–7% | W ≤ 105 avg · NP ≤ 120 · BPM ≤ 132 sustained · climbs to 150 W / 140 BPM | Tempo only. Pick *one* climb per trail to attack; soft-pedal the rest. No junk surges on flats. | 15–20 min. Real food (banana, rice cake, PB sandwich). | 80 g carbs · 600 mL water + electrolyte tab |
| **RECOVER** — defensive | 70–100% / 12%+ **or** 40–70% / 7–12% **or** <40% / 0–3% **or** <40% / 3–7% | W ≤ 85 avg · NP ≤ 100 · BPM ≤ 122 sustained · no climb effort > 120 W | Granny gear on climbs. Coast flats. Walk anything that would spike HR. No standing pedal strokes. | 20–30 min. Sit down. Big meal — sandwich + chips + a real Coke. Refill bottles cold. | 100 g carbs · 800 mL water + electrolyte + salt cap |
| **REST** — pre-trouble | 40–70% / 12%+ **or** <40% / 7–12% | W ≤ 65 avg · NP ≤ 80 · BPM ≤ 115 · walk anything > 90 W | Walk the technical bits. Soft-pedal everything else. Goal is to finish the trail, not race it. Stop mid-trail if you feel worse, not better. | **30–45 min in shade.** Off the bike, off your feet. Real meal. Reassess: do you actually want trail N+1? | 100+ g carbs · 1 L water + 2 electrolyte tabs |
| **STOP** — emergency | <40% / 12%+ **or** any / 18%+ | HR **must drop** to < 120 within 10 min off-bike — else DNF | Get to the next safe stop. Don't push for a finish split. | See "Trouble protocol" below. | Sip slowly, eat slowly. Forcing food when wrecked = vomiting. |

**Mapping to the on-device tile alerts** (the row 1–3 tiles flash/invert at these numbers, so the device tells you when you've drifted to the next mode):

- **W tile** — inverse at **120 W**, flashing at **135 W**
- **NP tile** — inverse at **128 W**, flashing at **145 W**
- **BPM tile** — inverse at **138 BPM**, flashing at **147 BPM**

PUSH mode = all tiles white (no alerts). One tile goes inverse → you've slipped to STEADY. Two tiles inverse, or any tile flashing → RECOVER or worse. BPM tile flashing at 147 with low W' Bal → you're hitting STOP territory regardless of EF Drift.

**Tile-color shortcut:**

- Both tiles in the **green** part of their range → **PUSH**
- Either tile in the **yellow** band, neither in red → **STEADY**
- One tile **red / orange** → **RECOVER**
- Both tiles in **red / orange** → **REST**
- W' Bal flashing OR EF ≥ 18% → **STOP**

---

## Underlying decision matrix (W'bal × EF drift — 12 cells)

For completeness — these are the cells that feed the mode table above.

| W'bal | EF | Action | Mode |
|-------|----|--------|------|
| 70–100% | 0–3% | Send the climb, push pace | PUSH |
| 70–100% | 3–7% | Send the climb, easy after | PUSH |
| 70–100% | 7–12% | Easy climb — save for finish | STEADY |
| 70–100% | 12%+ | **Don't dig** — preserve | RECOVER |
| 40–70% | 0–3% | Pick spots, no junk surges | STEADY |
| 40–70% | 3–7% | Selective efforts only | STEADY |
| 40–70% | 7–12% | Soft-pedal, eat, drink | RECOVER |
| 40–70% | 12%+ | **Recover hard** before next trail | REST |
| <40% | 0–3% | Soft-pedal, rebuild W' | RECOVER |
| <40% | 3–7% | Recover + refuel before next | RECOVER |
| <40% | 7–12% | Walk/coast, let HR drop, eat | REST |
| <40% | 12%+ | **TROUBLE — full stop** | STOP |

---

## Heuristics

- **Between-trail check (in the car):** EF jumped >3% last trail → next trail goes easier.
- **>1% EF drift per trail = started too hard.**
- **Both row-4 tiles green at hour 12 = winning.**
- **Walk a steep climb to recover W'** — it's free and fast.
- **Eat before you're hungry, drink before you're thirsty.** Once EF drift starts climbing, you're already behind.
- **W' Bal won't read 100% on cooked days** — that's intentional. Durability scaling shrinks effective CP/W' by ~2%/0.8% per 1000 kJ. By trail 9 your max-recovered W' might cap at 88%. If you see that, treat 88% as the new ceiling, not as a problem.

---

## Trouble protocol (W'bal <40% AND EF ≥12%)

1. Stop. Off the bike. Shade.
2. 500 mL water + electrolyte
3. 60–80 g carbs (gel, bar, real food)
4. 15 min rest minimum before next trail
5. **If HR doesn't drop in 10 min → DNF and call it.** Pride is recoverable. Heatstroke and cardiac events are not.

---

## Calibration anchors

- HRrest **52** · CP **171w** · W' **20 kJ**
- EF Drift validity band: **[0.55 × CP, 1.05 × CP] = 94–180 W** (only seconds in this band feed the model)
- EF baseline locks once **10 valid 1-min windows** accumulate — typically 20–25 min of clean steady-state (warmup 5:30 AM + first part of trail 1)
- After lock, EF display waits another **5 min** for the rolling buffer to fill before showing a number
- 5 AM reset boundary — all rides between 5 AM and next 5 AM share one event
- 2-min gap rule: if no power sample falls in the validity band for 2+ minutes (long coast / stop / techy descent), the EF rolling buffer clears and refills

---

## Pre-event checklist

- [ ] HR strap paired, fresh battery
- [ ] Power meter paired, calibrated
- [ ] Both bottles full, electrolyte mixed
- [ ] Food: ≥ 60 g carbs/hr × 8 riding hr = 500 g minimum
- [ ] Spare tube, plug kit, multi-tool, mini pump
- [ ] Phone charged, map of all 10 trails
- [ ] Sideloaded latest `830DataScreenJD.prg` build
- [ ] Garmin charged to 100%, charger in car for between trails
- [ ] Lights charged (last 1–2 trails likely in dark)
- [ ] Warmup ride 5:30 AM — easy spin, 10+ min steady in the 94–180 W band to seed the EF baseline before the start-line surge
