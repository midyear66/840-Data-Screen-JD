import Toybox.Application;
import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

// ─────────────────────────────────────────────────────────────────────────────
//  Judgment Day 2025 — Edge 840 Custom Data Field
//  FTP: 171w  |  Max HR: 174 bpm (recorded peak 177 bpm)  |  LTHR: ~147 bpm
//
//  ALERT SYSTEM — two-stage per tile:
//    WARNING  → solid inverse (black bg, white text) — "pay attention"
//    ALERT    → slow flash (~0.5 Hz) — "back off now"
//
//  COMBINED CONDITION — when power AND hr are both in warning or above,
//    both tiles flash in sync regardless of individual thresholds.
//
//  W' BALANCE (Skiba 2012) — anaerobic capacity remaining.
//    Drain: W'bal -= (power - CP) when power > CP
//    Recovery: W'bal += (W' - W'bal) / 550 when power <= CP  (τ = 550s)
//    Warning < 40%, Alert (flash) < 20%
//
//  STRAIN — Whoop-style cumulative cardiovascular load on a 0–21 scale.
//    Banister TRIMP (HRR-based) accumulated per second; mapped via
//    21 × (1 − e^(−TRIMP/K)). Persists across activities via
//    Application.Storage. Resets at 6 AM local — all rides between
//    6 AM and 6 AM count as one event (e.g., Judgment Day's 10 trails).
//    Display: "cumulative / +this-ride".
// ─────────────────────────────────────────────────────────────────────────────

class MyDataFieldView extends WatchUi.DataField {

    var _hr        as Lang.Number? = null;
    var _power     as Lang.Number? = null;
    var _normPower as Lang.Number? = null;
    var _distance  as Lang.Float?  = null;

    var _hrMiss    = 0;
    var _powerMiss = 0;

    // ── NP calculation state ──────────────────────────────────────────────────
    // Coggan NP: 4th root of rolling mean of (30s rolling avg power)^4
    var _npBuf     as Lang.Array<Lang.Number or Null>;  // 30-sample circular buffer
    var _npBufSum  as Lang.Number = 0;
    var _npIdx     as Lang.Number = 0;
    var _npCount   as Lang.Number = 0;
    var _npMean4   as Lang.Float  = 0.0;
    var _npSamples as Lang.Number = 0;

    // Miss tolerance before field shows "--"
    const MISS_THRESHOLD = 5;

    // ── Alert thresholds — loaded from user settings (Garmin Connect) ─────────
    // Defaults match Bob's physiology: FTP 171w, Max HR 174 bpm, LTHR ~147 bpm.
    var _hrWarn   as Lang.Number = 138;
    var _hrAlert  as Lang.Number = 147;
    var _pwrWarn  as Lang.Number = 120;
    var _pwrAlert as Lang.Number = 135;
    var _npWarn   as Lang.Number = 128;
    var _npAlert  as Lang.Number = 145;

    // ── Flash clock ───────────────────────────────────────────────────────────
    // onUpdate fires every ~1s — toggle each call gives ~0.5 Hz flash
    var _flashToggle as Lang.Boolean = false;

    // ── W' Balance (Skiba 2012) ───────────────────────────────────────────────
    var _wPrime        as Lang.Number  = 20000;
    var _cp            as Lang.Number  = 171;
    var _wPrimeBal     as Lang.Float   = 20000.0;
    var _wPrimeSeconds as Lang.Number  = 0;
    var _wPrimeValid   as Lang.Boolean = false;

    // ── Strain (Whoop-style cumulative load) ──────────────────────────────────
    var _hrRestVal as Lang.Number = 52;
    var _hrMaxVal  as Lang.Number = 174;
    var _strainK   as Lang.Number = 60;
    var _strain    as StrainTracker;

    function initialize() {
        DataField.initialize();

        _npBuf = new [30];
        for (var i = 0; i < 30; i++) { _npBuf[i] = 0; }

        loadSettings();
        _wPrimeBal = _wPrime.toFloat();  // sync after loadSettings() may change _wPrime

        _strain = new StrainTracker(_hrRestVal, _hrMaxVal, _strainK);
        _strain.onActivityStart();
    }

    // ── loadSettings() — read user-configured thresholds from storage ─────────
    function loadSettings() as Void {
        _hrWarn   = Application.Properties.getValue("hrWarn")   as Lang.Number;
        _hrAlert  = Application.Properties.getValue("hrAlert")  as Lang.Number;
        _pwrWarn  = Application.Properties.getValue("pwrWarn")  as Lang.Number;
        _pwrAlert = Application.Properties.getValue("pwrAlert") as Lang.Number;
        _npWarn   = Application.Properties.getValue("npWarn")   as Lang.Number;
        _npAlert  = Application.Properties.getValue("npAlert")  as Lang.Number;
        _wPrime   = Application.Properties.getValue("wPrime")   as Lang.Number;
        _cp       = Application.Properties.getValue("cp")       as Lang.Number;
        _hrRestVal = Application.Properties.getValue("hrRest")  as Lang.Number;
        _hrMaxVal  = Application.Properties.getValue("hrMax")   as Lang.Number;
        _strainK   = Application.Properties.getValue("strainK") as Lang.Number;
        // Clamp W'bal if user lowers W' mid-ride to prevent display > 100%
        if (_wPrimeBal > _wPrime.toFloat()) {
            _wPrimeBal = _wPrime.toFloat();
        }
    }

    // ── onSettingsChanged() — called when user edits settings in Garmin Connect
    function onSettingsChanged() as Void {
        loadSettings();
        if (_strain != null) {
            _strain.initialize(_hrRestVal, _hrMaxVal, _strainK);
        }
        WatchUi.requestUpdate();
    }

    // ── compute() — called ~1/sec by the device ───────────────────────────────
    function compute(info as Activity.Info) as Void {

        // Heart rate
        if (info.currentHeartRate != null) {
            _hr = info.currentHeartRate;
            _hrMiss = 0;
        } else {
            _hrMiss += 1;
            if (_hrMiss >= MISS_THRESHOLD) { _hr = null; }
        }

        // Instant power
        if (info.currentPower != null) {
            _power = info.currentPower;
            _powerMiss = 0;
        } else {
            _powerMiss += 1;
            if (_powerMiss >= MISS_THRESHOLD) { _power = null; }
        }

        // ── Normalized power (Coggan) ─────────────────────────────────────────
        var pSample = (_power != null) ? (_power as Lang.Number) : 0;
        _npBufSum  -= _npBuf[_npIdx];
        _npBuf[_npIdx] = pSample;
        _npBufSum  += pSample;
        _npIdx      = (_npIdx + 1) % 30;
        if (_npCount < 30) { _npCount += 1; }

        if (_npCount == 30) {
            var avg  = _npBufSum / 30.0;
            var avg4 = avg * avg * avg * avg;
            _npSamples += 1;
            _npMean4   += (avg4 - _npMean4) / _npSamples;
            _normPower  = Math.sqrt(Math.sqrt(_npMean4)).toNumber();
        }

        // Distance — convert meters to miles
        if (info.elapsedDistance != null) {
            _distance = info.elapsedDistance / 1609.344;
        }

        // ── W' Balance (Skiba 2012) ───────────────────────────────────────────
        // Only update when power is valid — no phantom recovery during dropouts
        if (_power != null) {
            var p      = (_power as Lang.Number).toFloat();
            var cpF    = _cp.toFloat();
            var wPrimeF = _wPrime.toFloat();

            if (p > cpF) {
                _wPrimeBal -= (p - cpF);
            } else {
                _wPrimeBal += (wPrimeF - _wPrimeBal) / 550.0;
            }

            if (_wPrimeBal < 0.0)      { _wPrimeBal = 0.0; }
            if (_wPrimeBal > wPrimeF)  { _wPrimeBal = wPrimeF; }

            _wPrimeSeconds += 1;
            if (_wPrimeSeconds >= 60) { _wPrimeValid = true; }
        }

        // ── Strain (Banister TRIMP, cumulative across event) ──────────────────
        _strain.update(_hr);
    }

    // ── onUpdate() — render the screen ───────────────────────────────────────
    function onUpdate(dc as Graphics.Dc) as Void {
        _flashToggle = !_flashToggle;

        var w    = dc.getWidth();
        var h    = dc.getHeight();
        var rowH = h / 4;
        var pad  = 4;

        // White background
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
        dc.clear();

        // ── Evaluate alert states ─────────────────────────────────────────────

        var pwrState = alertState(_power,     _pwrWarn, _pwrAlert);
        var npState  = alertState(_normPower, _npWarn,  _npAlert);
        var hrState  = alertState(_hr,        _hrWarn,  _hrAlert);

        var combined    = (pwrState >= 1 && hrState >= 1);
        var pwrInverse  = resolveInverse(pwrState, combined);
        var npInverse   = resolveInverse(npState,  false);
        var hrInverse   = resolveInverse(hrState,  combined);

        // ── W' Balance display and alert ──────────────────────────────────────
        var wBalStr     = "--";
        var wBalInverse = false;
        if (_wPrimeValid) {
            var wBalPct = (_wPrimeBal / _wPrime.toFloat() * 100.0).toNumber();
            wBalStr = wBalPct.toString();
            if (wBalPct < 20) {
                wBalInverse = _flashToggle;
            } else if (wBalPct < 40) {
                wBalInverse = true;
            }
        }

        // ── Strain display ────────────────────────────────────────────────────
        var strainStr = _strain.getCumulative().toString() + " / +" +
                        _strain.getRideDelta().toString();

        // ── Draw tiles ────────────────────────────────────────────────────────

        // Row 1: Power (left) | Normalized Power (right)
        drawCell(dc, 0,     0,        w / 2, rowH, _power     != null ? _power.toString()        : "--", "W",   false, pad, pwrInverse);
        drawCell(dc, w / 2, 0,        w / 2, rowH, _normPower != null ? _normPower.toString()     : "--", "NP",  false, pad, npInverse);

        // Row 2: Heart Rate
        drawCell(dc, 0,     rowH,     w,     rowH, _hr        != null ? _hr.toString()            : "--", "BPM", true,  pad, hrInverse);

        // Row 3: Distance
        drawCell(dc, 0, rowH * 2, w, rowH, _distance != null ? _distance.format("%.1f") : "--", "MI", true, pad, false);

        // Sensor battery overlay — lowest paired sensor < 10%
        var actInfo = Activity.getActivityInfo();
        if (actInfo != null && (actInfo has :sensorBatteries) && actInfo.sensorBatteries != null) {
            var batteries = actInfo.sensorBatteries;
            var lowestPct = 100.0;
            var keys = batteries.keys();
            for (var i = 0; i < keys.size(); i++) {
                var entry = batteries[keys[i]];
                if (entry != null) {
                    var pct = entry.battery;
                    if (pct != null && pct < lowestPct) { lowestPct = pct.toFloat(); }
                }
            }
            if (lowestPct < 10.0) {
                dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
                dc.drawText(w - pad, rowH * 2 + pad, Graphics.FONT_SMALL,
                            lowestPct.format("%.0f") + "%", Graphics.TEXT_JUSTIFY_RIGHT);
            }
        }

        // Row 4: W' Balance (left) | Strain (right)
        drawCell(dc,     0,     rowH * 3, w / 2, rowH, wBalStr,   "%",  false, pad, wBalInverse);
        drawCellText(dc, w / 2, rowH * 3, w / 2, rowH, strainStr, "ST", false, pad, false);

        // ── Red dividers ──────────────────────────────────────────────────────
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(w / 2, 0,         w / 2, rowH);      // row 1 vertical split
        dc.drawLine(0,     rowH,       w,     rowH);      // row 1/2
        dc.drawLine(0,     rowH * 2,   w,     rowH * 2); // row 2/3
        dc.drawLine(0,     rowH * 3,   w,     rowH * 3); // row 3/4
        dc.drawLine(w / 2, rowH * 3,   w / 2, h);        // row 4 vertical split
    }

    // ── alertState() ─────────────────────────────────────────────────────────
    // Returns 0 (normal), 1 (warning), or 2 (alert)
    function alertState(value as Lang.Number?, warnThreshold as Lang.Number,
                        alertThreshold as Lang.Number) as Lang.Number {
        if (value == null)           { return 0; }
        if (value >= alertThreshold) { return 2; }
        if (value >= warnThreshold)  { return 1; }
        return 0;
    }

    // ── resolveInverse() ─────────────────────────────────────────────────────
    // state 0 → normal, 1 → solid inverse, 2 → flash, combined → escalate to flash
    function resolveInverse(state as Lang.Number,
                            combined as Lang.Boolean) as Lang.Boolean {
        if (state == 0)             { return false; }
        if (state == 2 || combined) { return _flashToggle; }
        return true;
    }

    // ── fitNumberFont() ───────────────────────────────────────────────────────
    function fitNumberFont(maxHeight as Lang.Number) as Graphics.FontType {
        var fonts = [
            Graphics.FONT_NUMBER_THAI_HOT,
            Graphics.FONT_NUMBER_HOT,
            Graphics.FONT_NUMBER_MEDIUM,
            Graphics.FONT_NUMBER_MILD,
            Graphics.FONT_LARGE,
            Graphics.FONT_MEDIUM,
            Graphics.FONT_SMALL,
            Graphics.FONT_TINY,
            Graphics.FONT_XTINY
        ];
        for (var i = 0; i < fonts.size(); i++) {
            if (Graphics.getFontHeight(fonts[i]) <= maxHeight) {
                return fonts[i];
            }
        }
        return Graphics.FONT_XTINY;
    }

    // ── fitFont() ─────────────────────────────────────────────────────────────
    function fitFont(maxHeight as Lang.Number) as Graphics.FontType {
        var fonts = [
            Graphics.FONT_LARGE,
            Graphics.FONT_MEDIUM,
            Graphics.FONT_SMALL,
            Graphics.FONT_TINY,
            Graphics.FONT_XTINY
        ];
        for (var i = 0; i < fonts.size(); i++) {
            if (Graphics.getFontHeight(fonts[i]) <= maxHeight) {
                return fonts[i];
            }
        }
        return Graphics.FONT_XTINY;
    }

    // ── drawCell() ────────────────────────────────────────────────────────────
    // Renders a single tile: value in left 75%, unit label in right 25%
    // inverse=true fills black background with white text
    function drawCell(dc as Graphics.Dc,
                      x as Lang.Number, y as Lang.Number,
                      cellW as Lang.Number, cellH as Lang.Number,
                      value as Lang.String, unit as Lang.String,
                      leftUnit as Lang.Boolean, pad as Lang.Number,
                      inverse as Lang.Boolean) as Void {

        var cy        = y + cellH / 2;
        var valueW    = cellW * 3 / 4;
        var unitW     = cellW - valueW;
        var valueFont = fitNumberFont(cellH);
        var unitFont  = fitFont(cellH);

        if (inverse) {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            dc.fillRectangle(x, y, cellW, cellH);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        }

        dc.drawText(x + valueW / 2, cy, valueFont, value,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(inverse ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK,
                    Graphics.COLOR_TRANSPARENT);
        var unitJustify = leftUnit
            ? Graphics.TEXT_JUSTIFY_LEFT
            : Graphics.TEXT_JUSTIFY_CENTER;
        var unitX = leftUnit ? x + valueW : x + valueW + unitW / 2;
        dc.drawText(unitX, cy, unitFont, unit,
                    unitJustify | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ── drawCellText() ────────────────────────────────────────────────────────
    // Like drawCell() but uses a text font for the value. Required when the
    // value string contains non-digit characters (e.g., "14 / +2") since the
    // NUMBER_HOT font family is digit-only.
    function drawCellText(dc as Graphics.Dc,
                          x as Lang.Number, y as Lang.Number,
                          cellW as Lang.Number, cellH as Lang.Number,
                          value as Lang.String, unit as Lang.String,
                          leftUnit as Lang.Boolean, pad as Lang.Number,
                          inverse as Lang.Boolean) as Void {

        var cy        = y + cellH / 2;
        var valueW    = cellW * 3 / 4;
        var unitW     = cellW - valueW;
        var valueFont = fitFont(cellH);
        var unitFont  = fitFont(cellH);

        if (inverse) {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            dc.fillRectangle(x, y, cellW, cellH);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        }

        dc.drawText(x + valueW / 2, cy, valueFont, value,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(inverse ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK,
                    Graphics.COLOR_TRANSPARENT);
        var unitJustify = leftUnit
            ? Graphics.TEXT_JUSTIFY_LEFT
            : Graphics.TEXT_JUSTIFY_CENTER;
        var unitX = leftUnit ? x + valueW : x + valueW + unitW / 2;
        dc.drawText(unitX, cy, unitFont, unit,
                    unitJustify | Graphics.TEXT_JUSTIFY_VCENTER);
    }

}
