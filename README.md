# MyDataField

A custom Garmin Connect IQ data field for the Edge 840 (and compatible devices) that displays four key cycling metrics in a clean, high-visibility layout.

## Layout

```
┌─────────────┬─────────────┐
│   POWER     │   AVG PWR   │
├─────────────┴─────────────┤
│         HEART RATE    BPM │
├───────────────────────────┤
│           CADENCE     RPM │
├───────────────────────────┤
│          DISTANCE      MI │
└───────────────────────────┘
```

- **Row 1:** Current power and average power (split 50/50)
- **Row 2:** Heart rate with BPM unit
- **Row 3:** Cadence with RPM unit
- **Row 4:** Distance in miles

### Features

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
