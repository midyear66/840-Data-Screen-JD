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
│  W'bal   %  │   PC     PC │  row 4 — anaerobic reserve | performance condition
└─────────────┴─────────────┘
```

- **Row 1:** Instant power (W) on the left; Coggan Normalized Power (NP) on the right. Red vertical divider.
- **Row 2:** Heart rate (BPM), full width.
- **Row 3:** Elapsed distance in miles. When any paired sensor battery drops below 10%, the lowest percentage is overlaid in red (top-right corner of this tile).
- **Row 4:** W' Balance percentage (left) and Garmin Performance Condition (right). Red vertical divider.

All rows are separated by red horizontal dividers.

---

## Metrics

### W' Balance (Skiba 2012)
Tracks remaining anaerobic capacity as a percentage of your total W' reserve.

- **Drain:** every second above Critical Power (CP), `W'bal -= power - CP`
- **Recovery:** every second at or below CP, `W'bal += (W' - W'bal) / 550` (τ = 550 s)
- Shows `--` for the first 60 seconds of valid power data
- Alerts when stamina is running low

### Performance Condition
Garmin's built-in Firstbeat metric — a real-time assessment of your ability to perform compared to your average fitness level, derived from power, heart rate, and HRV. Read directly from `Activity.Info.currentPerformanceCondition` so the number shown on the tile matches the Performance Condition graph in Garmin Connect for the same ride.

- Shows `--` until the Edge establishes a value (typically 6–20 minutes in)
- Displayed as a signed integer. Garmin's scale: `> 10` excellent, `2..10` good, `-1..1` baseline, `-10..-2` fair, `-20..-11` poor
- No drift during coasting or stops — the device freezes the last value instead of decaying it

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
| Instant power | ≥ 120w | ≥ 135w |
| Normalized power | ≥ 128w | ≥ 145w |
| Heart rate | ≥ 138 bpm | ≥ 147 bpm |
| W' Balance | < 40% | < 20% (flash) |
| Performance Condition | — | — (display only) |

### Combined Condition
When **both** instant power and HR are at warning or above simultaneously, both tiles escalate to flashing regardless of their individual alert thresholds. This catches the "quietly overcooked" scenario single-metric alerts miss.

Note: W' Balance alerts are intentionally inverted — low values are bad — so they are handled independently from the combined condition. Performance Condition is currently display-only (no warning/alert styling).

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
| Critical Power (w) | 171 | Threshold between aerobic and anaerobic (≈ FTP) |

**In the simulator:** Settings → open the settings dialog for the data field.

**On device:** Edit default values in `resources/properties.xml` and rebuild/reinstall.

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
