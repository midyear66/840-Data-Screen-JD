# MyDataField

A custom Garmin Connect IQ data field for the Edge 840 (and compatible devices) that displays four key cycling metrics in a clean, high-visibility layout — with a two-stage alert system tuned for hot-weather Z2 riding.

## Layout

```
┌─────────────┬─────────────┐
│   POWER  W  │   NP     NP │
├─────────────┴─────────────┤
│          HEART RATE   BPM │
├───────────────────────────┤
│            CADENCE    RPM │
├───────────────────────────┤
│           DISTANCE     MI │
└───────────────────────────┘
```

- **Row 1:** Instant power (left) and Normalized Power — Coggan 30s rolling NP (right)
- **Row 2:** Heart rate with BPM unit
- **Row 3:** Cadence with RPM unit
- **Row 4:** Distance in miles

Rows are separated by red dividers.

---

## Alert System

Each of the power and HR tiles uses a **two-stage alert**:

| Stage | Display | Meaning |
|-------|---------|---------|
| Normal | Black text on white | Within zone |
| Warning | Solid inverse (white text, black bg) | Approaching limit — pay attention |
| Alert | Slow flash (~0.5 Hz) | Over limit — back off now |

### Thresholds (tuned for FTP 171w, Max HR 174 bpm, LTHR ~147 bpm)

| Metric | Warning | Alert |
|--------|---------|-------|
| Instant power | 120w (approaching Z2 ceiling) | 135w (into Z3) |
| Normalized power | 128w | 145w |
| Heart rate | 138 bpm (top of Z3) | 147 bpm (LTHR) |

### Combined Condition
When **both** instant power and HR are at warning or above simultaneously, both tiles escalate to flashing — even if neither has crossed its individual alert threshold. This catches the "quietly overcooked" scenario that single-metric alerts miss.

### Low-Power / Bonk Alert
If instant power stays below 88w (Z2 floor) for 60+ consecutive seconds **and** HR is also dropping below 122 bpm, the cadence tile flashes as a fatigue/bonk check.

---

## Other Features

- Fonts scale to fill each row for maximum readability
- Displays `--` until a sensor connects
- Returns to `--` after 5 consecutive missed sensor readings
- Red battery warning (`X%`) appears in the cadence tile when battery drops below 10%

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
3. The compiled `.prg` file will be output to `bin/MyDataField.prg`

Or from the terminal:

```bash
java -Xms1g -jar /path/to/connectiq-sdk/bin/monkeybrains.jar \
  -o bin/MyDataField.prg \
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
6. Drag `bin/MyDataField.prg` into the `Apps/` folder
7. Safely eject the device and disconnect
8. On your Edge 840, add the data field to a training screen via **Settings → Activity Profiles → [Profile] → Data Screens**

---

## Simulator

To test without a physical device:

1. Run **Monkey C: Run** from the VS Code command palette (not "Run Test")
2. The Connect IQ simulator will launch
3. Start a simulated activity to see the data field render with live simulated sensor data

---

## License

MIT
