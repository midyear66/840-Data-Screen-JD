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
//    ALERT    → slow flash (~1 Hz) — "back off now"
//
//  COMBINED CONDITION — when power AND hr are both in warning or above,
//    both tiles flash in sync regardless of individual thresholds.
//    This catches "quietly overcooked" before either metric hits alert alone.
//
//  LOW POWER — if instant power stays below PWR_LOW for 60+ seconds
//    AND hr is also dropping, cadence tile flashes as bonk/fatigue check.
// ─────────────────────────────────────────────────────────────────────────────

class MyDataFieldView extends WatchUi.DataField {

    var _hr         as Lang.Number?  = null;
    var _cadence    as Lang.Number?  = null;
    var _power      as Lang.Number?  = null;
    var _normPower  as Lang.Number?  = null;
    var _distance   as Lang.Float?   = null;

    var _hrMiss      = 0;
    var _cadenceMiss = 0;
    var _powerMiss   = 0;

    // ── NP calculation state ──────────────────────────────────────────────────
    // Coggan NP: 4th root of rolling mean of (30s rolling avg power)^4
    var _npBuf     as Lang.Array<Lang.Number or Null>;  // 30-sample circular buffer
    var _npBufSum  as Lang.Number  = 0;         // running sum of buffer contents
    var _npIdx     as Lang.Number  = 0;         // next write position (0–29)
    var _npCount   as Lang.Number  = 0;         // samples written so far (caps at 30)
    var _npMean4   as Lang.Float   = 0.0;       // Welford running mean of rollingAvg^4
    var _npSamples as Lang.Number  = 0;         // denominator for Welford mean

    // Miss tolerance before field shows "--"
    const MISS_THRESHOLD = 5;

    // ── HR thresholds (bpm) ───────────────────────────────────────────────────
    // Max HR 174 bpm. Z3 aerobic ceiling = 137 bpm. LTHR ~147 bpm.
    // Heat ceiling is top of Z3 — beyond that cardiac drift in 95°F+ is unsafe.
    const HR_WARN   = 138;   // solid inverse  — top of Z3, entering threshold
    const HR_ALERT  = 147;   // slow flash     — at LTHR, hard stop in heat

    // ── Instant power thresholds (watts) ─────────────────────────────────────
    // Z2 = 96–128w. Warn before ceiling, alert above ceiling.
    const PWR_WARN   = 120;  // solid inverse  — approaching Z2 ceiling
    const PWR_ALERT  = 135;  // slow flash     — into Z3, burning matches
    const PWR_LOW    = 88;   // low alert      — below Z2 floor (bonk watch)

    // ── Normalized power thresholds (watts) ──────────────────────────────────
    // NP runs 15–25% higher than avg on trail — needs its own higher thresholds
    const NP_WARN    = 128;  // solid inverse  — sustained effort getting costly
    const NP_ALERT   = 145;  // slow flash     — trail variability adding up

    // ── Low power bonk detection ──────────────────────────────────────────────
    // If power stays below PWR_LOW for this many compute cycles (~60 sec),
    // trigger cadence tile flash as fatigue/bonk check
    const LOW_PWR_CYCLES = 60;
    var _lowPwrCount = 0;

    // ── Flash clock ───────────────────────────────────────────────────────────
    // onUpdate fires every ~1s on Edge 840 datafields — toggle each call
    // gives ~0.5 Hz flash (1 sec on, 1 sec off) which is readable on trail
    var _flashToggle as Lang.Boolean = false;

    function initialize() {
        DataField.initialize();
        _npBuf = new [30];
        for (var i = 0; i < 30; i++) { _npBuf[i] = 0; }
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

        // Cadence
        if (info.currentCadence != null) {
            _cadence = info.currentCadence;
            _cadenceMiss = 0;
        } else {
            _cadenceMiss += 1;
            if (_cadenceMiss >= MISS_THRESHOLD) { _cadence = null; }
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
        // Push current power (0 if no signal) into 30s circular buffer,
        // then accumulate a Welford running mean of (rollingAvg^4).
        // NP = 4th root of that mean — valid once buffer is full (30 samples).
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

        // ── Low power bonk counter ────────────────────────────────────────────
        // Count consecutive seconds below PWR_LOW
        if (_power != null && _power < PWR_LOW) {
            _lowPwrCount += 1;
        } else {
            _lowPwrCount = 0;  // reset as soon as power rises
        }
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

        // Instant power state
        var pwrState = alertState(_power, PWR_WARN, PWR_ALERT);

        // Normalized power state
        var npState  = alertState(_normPower, NP_WARN, NP_ALERT);

        // HR state
        var hrState  = alertState(_hr, HR_WARN, HR_ALERT);

        // ── Combined condition ────────────────────────────────────────────────
        // If BOTH power and HR are at warning or above, escalate both to flash.
        // This catches the "quietly overcooked" scenario single metrics miss.
        var combined = (pwrState >= 1 && hrState >= 1);

        // Resolve final inverse flags
        // State: 0 = normal, 1 = warning (solid inverse), 2 = alert (flash)
        var pwrInverse  = resolveInverse(pwrState,  combined);
        var npInverse   = resolveInverse(npState,   false);     // NP independent
        var hrInverse   = resolveInverse(hrState,   combined);

        // ── Low power / bonk alert on cadence tile ────────────────────────────
        // Flash cadence tile if power has been below Z2 floor for 60+ seconds
        // AND HR is also dropping (hr below Z3 floor = 128 bpm)
        var bonkAlert = false;
        if (_lowPwrCount >= LOW_PWR_CYCLES) {
            if (_hr != null && _hr < 122) {  // below Z3 floor (70% of 174 max)
                bonkAlert = _flashToggle;  // flash cadence tile
            }
        }

        // ── Draw tiles ────────────────────────────────────────────────────────

        // Row 1: Power (left) | Normalized Power (right)
        drawCell(dc, 0,     0, w / 2, rowH, _power     != null ? _power.toString()          : "--", "W",  false, pad, pwrInverse);
        drawCell(dc, w / 2, 0, w / 2, rowH, _normPower != null ? _normPower.toString()       : "--", "NP", false, pad, npInverse);

        // Row 2: Heart Rate
        drawCell(dc, 0, rowH,     w, rowH, _hr       != null ? _hr.toString()               : "--", "BPM", true, pad, hrInverse);

        // Row 3: Cadence — flashes on bonk alert
        drawCell(dc, 0, rowH * 2, w, rowH, _cadence  != null ? _cadence.toString()          : "--", "RPM", true, pad, bonkAlert);

        // Battery warning on cadence tile when < 10%
        var battery = System.getSystemStats().battery;
        if (battery < 10.0) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w - pad, rowH * 2 + pad, Graphics.FONT_SMALL,
                        battery.format("%.0f") + "%", Graphics.TEXT_JUSTIFY_RIGHT);
        }

        // Row 4: Distance
        drawCell(dc, 0, rowH * 3, w, rowH, _distance != null ? _distance.format("%.1f")     : "--", "MI",  true, pad, false);

        // ── Red dividers ──────────────────────────────────────────────────────
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(w / 2, 0,       w / 2, rowH);
        dc.drawLine(0,     rowH,     w,     rowH);
        dc.drawLine(0,     rowH * 2, w,     rowH * 2);
        dc.drawLine(0,     rowH * 3, w,     rowH * 3);
    }

    // ── alertState() ─────────────────────────────────────────────────────────
    // Returns 0 (normal), 1 (warning), or 2 (alert)
    // value: the metric, warnThreshold / alertThreshold: the two levels
    function alertState(value as Lang.Number?, warnThreshold as Lang.Number,
                        alertThreshold as Lang.Number) as Lang.Number {
        if (value == null)                   { return 0; }
        if (value >= alertThreshold)         { return 2; }
        if (value >= warnThreshold)          { return 1; }
        return 0;
    }

    // ── resolveInverse() ─────────────────────────────────────────────────────
    // Converts alert state + combined flag into a boolean for drawCell
    //   state 0 → normal (false)
    //   state 1 → solid inverse (true, no flash)
    //   state 2 → slow flash (_flashToggle)
    //   combined → escalate to flash even if state is only 1
    function resolveInverse(state as Lang.Number,
                            combined as Lang.Boolean) as Lang.Boolean {
        if (state == 0)                      { return false; }
        if (state == 2 || combined)          { return _flashToggle; }
        return true;  // state 1, not combined — solid inverse
    }

    // ── fitNumberFont() ───────────────────────────────────────────────────────
    // Largest numeric font that fits maxHeight
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
    // Largest general font that fits maxHeight
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
    // Renders a single tile with value (left 75%) and unit label (right 25%)
    // inverse=true fills black background with white text
    function drawCell(dc as Graphics.Dc,
                      x as Lang.Number, y as Lang.Number,
                      cellW as Lang.Number, cellH as Lang.Number,
                      value as Lang.String, unit as Lang.String,
                      leftUnit as Lang.Boolean, pad as Lang.Number,
                      inverse as Lang.Boolean) as Void {

        var cy         = y + cellH / 2;
        var valueW     = cellW * 3 / 4;
        var unitW      = cellW - valueW;
        var valueFont  = fitNumberFont(cellH);
        var unitFont   = fitFont(cellH);

        if (inverse) {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            dc.fillRectangle(x, y, cellW, cellH);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        }

        // Value — centered in left 75% of tile
        dc.drawText(x + valueW / 2, cy, valueFont, value,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Unit label — right 25% of tile
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
