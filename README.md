# MyJDScreen

A custom Garmin Connect IQ data field for the Edge 840 built for **Judgment Day** — a 10-trail, 24-hour, ~70-mile mountain bike event. Optimized for Z2 ultra-endurance pacing with real-time stamina and fatigue indicators.

## Layout

```
┌─────────────┬─────────────┐
│   POWER  W  │   NP     NP │  row 1 — instant power | normalized power
├─────────────┴─────────────┤
│          HEART RATE   BPM │  row 2 — heart rate
├───────────────────────────┤
│           DISTANCE     MI │  row 3 — elapsed distance
├─────────────┬─────────────┤
│  W'bal   %  │   EF     EF │  row 4 — anaerobic reserve | EF drift vs baseline
└─────────────┴─────────────┘
```

- **Row 1:** Power (W) on the left — 3-second rolling average for display + alert state, to cut MTB pedal-stroke flicker; Coggan Normalized Power (NP) on the right. Red vertical divider.
- **Row 2:** Heart rate (BPM), full width.
- **Row 3:** Elapsed distance in miles. When any paired sensor battery drops below 10%, the lowest percentage is overlaid in red (top-right corner of this tile).
- **Row 4:** W' Balance percentage (left) and EF Drift (right) — % HR-rise for same power vs the morning baseline. Red vertical divider.

All rows are separated by red horizontal dividers.

---

## Metrics

### W' Balance (Skiba 2012, durability-scaled)
Tracks remaining anaerobic capacity as a percentage of your total W' reserve.

- **Drain:** every second above Critical Power (CP), `W'bal -= power - CP`
- **Recovery:** every second at or below CP, `W'bal += (W' - W'bal) / 550` (τ = 550 s)
- Shows `--` for the first 60 seconds of valid power data
- Alerts when stamina is running low

**Durability scaling.** As cumulative kJ of work accumulates across the event-day, effective CP and W' shrink — the body genuinely loses sustainable power and anaerobic capacity over hours of hard riding (Spragg/Maunder/Clark/Pugh durability research, 2018–2024). A 175 W push that didn't dent W' on trail 1 may drain it quickly on trail 9 because effective CP has dropped 5–10%. Coefficients tuned to published trained-cyclist data:

```
CP_effective = CP × (1 − 0.020 × kJ_total/1000)   // ~2% per 1000 kJ
W'_effective = W' × (1 − 0.008 × kJ_total/1000)   // ~0.8% per 1000 kJ
```

Floored at 0.7× to prevent absurd values. Cumulative kJ persists across rides via `Application.Storage` with the same 5 AM reset boundary as EF Drift.

### EF Drift
Coggan/Friel **Efficiency Factor decoupling** — the cumulative-fatigue gold standard from *Training and Racing with a Power Meter* (Allen & Coggan). Unlike Strain (which saturates near 21 by hour 8 of a 24-hour event), EF drift never saturates, and it's grounded in measurable physiology rather than a tunable constant.

**Formula.**

```
EF       = power / HR
drift    = (EF_baseline / EF_current) − 1     (positive = HR rising for same
                                               power = cumulative fatigue)
```

**Underlying physiology.** As you fatigue, HR rises at the same wattage because of plasma volume loss (cardiovascular drift, Coyle 1990s), thermoregulatory shunt, glycogen depletion forcing recruitment of less-efficient muscle fibers, and elevated sympathetic drive.

**Reading guide.**

| Drift | Meaning |
|-------|---------|
| 0–3% | Well-paced — sustainable indefinitely |
| 3–7% | Warming to fatigue — monitor |
| 7–12% | Cooked — eat, drink, cool down |
| 12–18% | Dial back hard |
| 18%+ | Pull-out territory |

(Allen & Coggan: <5% within a single ride = well-paced aerobic effort.)

**Baseline establishment.** Opportunistic. Collect valid 1-min windows until **10** windows accumulate (~20–25 min of clean steady-state, depending on how much of the ride falls inside the validity gate). Typically locks during a 5:30 AM warmup or early in trail 1. Tile shows `--` until baseline locks. The 10-window lock was validated against the full 36-ride power library (`tools/eval-rides.py`): dropping it from 15 raised the baseline-lock rate from 81% to 92% of powered rides and cut median time-to-lock from 35 to 24 min, while leaving the displayed validity band untouched so rolled-drift jitter stays in target (median 2.3%, max 4.6%). A 10-min warmup now suffices to seed the baseline before the start-line surge.

**Validity gate (sustained-aerobic only).** A second contributes to baseline/drift only when the 30-second rolling power lies in **[0.55×CP, 1.05×CP]** *and* HR > HRrest+20. The dual band filters both coasting *and* burst climbs above CP — both contaminate the rolling EF on bursty MTB and would otherwise produce nonsensical drift readings on punchy terrain. The band was calibrated against six MTB rides: tightening from the original 0.50–1.10 reduced per-minute drift jitter from 10–27% to 3–7% while still locking the baseline within the first half-hour of typical riding.

**Smoothing.** Live EF uses a **10-minute rolling average** of valid 1-min windows. The displayed drift is hidden until the rolling buffer has at least 5 windows (the first ~5 min post-lock are not yet stable enough to report). If no sample passes the gate for 120 seconds (long coast, stop, or technical descent), the rolling buffer is cleared so the live EF doesn't stitch across non-contiguous efforts.

**Event accumulation — 5 AM reset.** Baseline + last drift persist across activity stop/start, power-off, and reboot via `Application.Storage`. All rides started between **5 AM local and the next 5 AM local** share the same baseline — perfect for Judgment Day's 10-trail, 24-hour format. The 5 AM (rather than 6 AM) boundary lets a pre-event warm-up ride seed the baseline cleanly, before the start-line surge of trail 1 contaminates it.

**Resume behavior.** On power-on, the tile shows the last persisted drift % immediately; the live rolling buffer refills in the background and the display transitions to live once 5 valid 1-min windows have accumulated post-resume.

### Combined row-4 usage

The two row-4 tiles answer different pacing questions on different timescales — W' Balance for the next climb (seconds), EF drift for the whole event (hours).

| W' Bal | EF drift | What to do |
|---|---|---|
| 70–100% | 0–3% | Send the climb, push the pace |
| 70–100% | 3–7% | Send the climb but easy recovery after |
| 70–100% | 7–12% | Easy on the climb — save it for the finish |
| 70–100% | 12%+ | **Don't dig** — preserve everything you have |
| 40–70% | 0–3% | Pick spots, no junk surges |
| 40–70% | 3–7% | Selective efforts only |
| 40–70% | 7–12% | Soft-pedal, eat, drink |
| 40–70% | 12%+ | **Recover hard** before next trail |
| <40% | 0–3% | You went too hard recently; soft-pedal to rebuild W' |
| <40% | 3–7% | Recover + refuel before next effort |
| <40% | 7–12% | Walk/coast — let HR drop, eat |
| <40% | 12%+ | **Trouble** — full stop, eat, drink, reassess |

**Heuristics for JD:**
- Glance at EF drift between trails (in the car). If it jumped >3% on the last trail, the next trail goes easier.
- W' Balance is for in-trail climb decisions only — don't watch it on flats.
- EF drift trending up faster than 1% per trail = started too hard.
- Both numbers green at hour 12 = winning.

### Power display (3-second smoothing)
The W tile and its alert thresholds use a 3-second rolling average of raw power. On bursty MTB terrain, raw 1-second power produces ~7 warn-line crossings per minute from pedal-stroke and quantization noise alone, which strobes the tile unreadably. 3-second smoothing cuts alert-state transitions 30–40% across six validation rides while preserving real terrain response. The underlying NP, W' Balance, EF Drift, and durability accumulators still consume the raw 1-Hz power stream — smoothing is display-and-alert only.

### Normalized Power
Coggan algorithm: 4th root of the Welford running mean of (30-second rolling average power)⁴. Valid once 30 seconds of data have accumulated.

---

## Alert System

Each metric uses a **two-stage alert**:

| Stage | Display | Meaning |
|-------|---------|---------|
| Normal | Black text on white | Within target range |
| Warning | Solid inverse (white text, black bg) | Approaching limit — pay attention |
| Alert | Slow flash (~0.5 Hz) | Over limit — act now |

### Per-metric thresholds (defaults tuned for FTP 171w, Max HR 174 bpm, LTHR ~147 bpm)

| Metric | Warning | Alert |
|--------|---------|-------|
| Power (3-sec avg) | ≥ 120w | ≥ 135w |
| Normalized power | ≥ 128w | ≥ 145w |
| Heart rate | ≥ 138 bpm | ≥ 147 bpm |
| W' Balance | < 40% | < 20% (flash) |
| EF Drift | — | — (display only) |

### Combined Condition
When **both** instant power and HR are at warning or above simultaneously, both tiles escalate to flashing regardless of their individual alert thresholds. This catches the "quietly overcooked" scenario single-metric alerts miss.

Note: W' Balance alerts are intentionally inverted — low values are bad — so they are handled independently from the combined condition. EF Drift is currently display-only (no warning/alert styling).

---

## Configuring Settings

All thresholds and model parameters are configurable without recompiling.

| Setting | Default | Description |
|---------|---------|-------------|
| HR Warning (bpm) | 138 | Solid inverse — entering threshold territory |
| HR Alert (bpm) | 147 | Flashing — at LTHR, back off |
| Power Warning (w) | 120 | Solid inverse — approaching Z2 ceiling |
| Power Alert (w) | 135 | Flashing — into Z3 |
| NP Warning (w) | 128 | Solid inverse — sustained effort getting costly |
| NP Alert (w) | 145 | Flashing — trail variability adding up |
| W' Capacity (J) | 20000 | Total anaerobic reserve in joules |
| Critical Power (w) | 171 | Threshold between aerobic and anaerobic (≈ FTP); also defines the EF Drift validity band [0.55×CP, 1.05×CP] |
| Resting HR (bpm) | 52 | HRrest — used by EF Drift validity gate (HR > HRrest+20) |

**In the simulator:** Settings → open the settings dialog for the data field.

**On device:** Edit default values in `resources/properties.xml` and rebuild/reinstall.

---

## Companion docs

Two markdown documents at the repo root accompany the data field, intended for in-car reference between trails:

- **`cheatsheet.md`** — single-page Judgment Day pacing reference: tile reading guide, 5-mode action table (PUSH / STEADY / RECOVER / REST / STOP), W'Bal × EF Drift decision matrix, per-mode fuel and water targets, trouble protocol.
- **`trail-log.md`** — fillable per-trail log for the 24-hour event: W'Bal / EF Drift / Garmin Stamina / RPE per trail, trail-to-trail decision rules, end-of-event summary.

Build print-ready landscape PDFs (gitignored — regenerate any time):

```bash
pip3 install markdown-pdf
python3 tools/build-pdf.py
```

Outputs `cheatsheet.pdf`, `trail-log.pdf`, and `JD-pacing-packet.pdf` (combined) at the repo root.

---

## Requirements

- [Garmin Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) 9.x or later
- [Visual Studio Code](https://code.visualstudio.com/) with the [Monkey C extension](https://marketplace.visualstudio.com/items?itemName=garmin.monkey-c)
- A Garmin developer key (see [Garmin Developer Docs](https://developer.garmin.com/connect-iq/connect-iq-basics/getting-started/))
- Target device: Edge 840 (or other Connect IQ compatible cycling computers)

---

## Build

1. Open the project folder in VS Code
2. Run **Monkey C: Build for Device** from the command palette
3. The compiled `.prg` file will be output to `bin/830DataScreenJD.prg`

Or from the terminal:

```bash
java -Xms1g -jar /path/to/connectiq-sdk/bin/monkeybrains.jar \
  -o bin/830DataScreenJD.prg \
  -f monkey.jungle \
  -y /path/to/developer_key \
  -d edge840_sim -w
```

---

## Install on Device (Mac)

Use **[OpenMTP](https://github.com/ganeshrvel/openmtp)** to transfer files to your Garmin device via USB on macOS (macOS does not natively support MTP).

1. **Download and install OpenMTP** from [https://github.com/ganeshrvel/openmtp](https://github.com/ganeshrvel/openmtp)
2. **Quit Garmin Express completely** (including the menu bar icon) — only one MTP app can connect at a time
3. Connect your Garmin Edge 840 to your Mac via USB
4. Open OpenMTP — your device should appear in the file browser
5. Navigate to `GARMIN/Apps/` on the device
6. Drag `bin/830DataScreenJD.prg` into the `Apps/` folder
7. Safely eject the device and disconnect
8. On your Edge 840, add the data field to a training screen via **Settings → Activity Profiles → [Profile] → Data Screens**

---

## Simulator

1. Run **Monkey C: Run** from the VS Code command palette (not "Run Test")
2. The Connect IQ simulator will launch
3. Start a simulated activity to see the data field render with live simulated sensor data

---

## License

MIT
