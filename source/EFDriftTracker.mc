import Toybox.Application;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

// ─────────────────────────────────────────────────────────────────────────────
//  EFDriftTracker — Coggan/Friel Efficiency Factor decoupling, persistent
//  across power-off and across multiple rides in an event-day window.
//
//  EF       = power / HR
//  drift    = (EF_baseline / EF_current) − 1   (positive = HR rising for same
//             power = cumulative fatigue)
//
//  Validity gate (sustained-aerobic only): a sample counts only when the
//  30-sec rolling power lies in [0.55×CP, 1.05×CP] AND HR > HRrest + 20.
//  This filters BOTH coasting AND burst climbs above CP — both contaminate
//  the rolling EF on bursty MTB and would otherwise produce nonsensical
//  negative drift readings. The tightened band (vs the original 0.50–1.10)
//  was validated against six MTB rides — it drops per-minute drift jitter
//  from 10–27% down to 3–7%.
//
//  Baseline locks once 10 valid 1-min windows accumulate. Validated against
//  the full 36-ride power library (eval-rides.py): dropping the lock from 15
//  to 10 windows raised the baseline-lock rate from 81% to 92% of powered
//  rides and cut median time-to-lock from 35 to 24 min, while the displayed
//  validity band stays 0.55-1.05x CP so rolled-drift jitter holds in target
//  (median 2.3%, max 4.6% — well under the 7% ceiling). A 10-min warm-up now
//  suffices to seed the baseline before the start-line surge. The live EF is
//  a 10-minute rolling average; the displayed drift is hidden until the
//  rolling buffer holds at least 5 windows (5 min post-lock) so the first
//  number the rider sees is not a single-minute snapshot.
//
//  If no sample passes the gate for 120 seconds (long coast / stop /
//  technical descent), the rolling buffer is cleared so we don't stitch a
//  stale 10-min EF across non-contiguous efforts.
//
//  Reset at 5 AM local: a pre-event warm-up at 5:30 AM seeds the baseline,
//  and any rides between 5 AM and the next 5 AM share it. Cleaner than
//  using trail 1's first minutes (start-line surge contaminates the lock).
// ─────────────────────────────────────────────────────────────────────────────

class EFDriftTracker {

    const STORAGE_BASELINE    = "efBaseline";
    const STORAGE_LAST_UPDATE = "efLastUpdate";
    const STORAGE_LAST_DRIFT  = "efLastDrift";
    const STORAGE_LOCKED      = "efLocked";

    const HR_FLOOR_MARGIN      = 20;
    const WINDOW_SECONDS       = 60;
    const BASELINE_WINDOWS     = 10;     // 1-min valid windows needed to lock
    const ROLLING_WINDOWS      = 10;     // post-lock rolling EF window (min)
    const ROLLING_MIN_DISPLAY  = 5;      // hide drift until this many windows
    const SAVE_INTERVAL_TICKS  = 60;
    const POWER_ROLL_SECONDS   = 30;     // smooth instantaneous bursts
    const POWER_BAND_LOW_FRAC  = 0.55;   // require sustained aerobic effort
    const POWER_BAND_HIGH_FRAC = 1.05;   // exclude burst climbs above CP
    const GAP_RESET_SECONDS    = 120;    // clear rolling buf if gated out

    var _hrRest as Lang.Number  = 52;
    var _cp     as Lang.Number  = 171;
    var _powerBandLow  as Lang.Float = 0.0;
    var _powerBandHigh as Lang.Float = 0.0;

    // 30-sec rolling power buffer (for the validity gate)
    var _rollPwrBuf   as Lang.Array<Lang.Number or Null>;
    var _rollPwrIdx   as Lang.Number = 0;
    var _rollPwrCount as Lang.Number = 0;
    var _rollPwrSum   as Lang.Number = 0;

    var _baselineEF       as Lang.Float   = 0.0;
    var _baselineLocked   as Lang.Boolean = false;
    var _validWindowCount as Lang.Number  = 0;
    var _baselineHRSum    as Lang.Float   = 0.0;
    var _baselinePowerSum as Lang.Float   = 0.0;

    // Current 1-min window accumulators
    var _windowHRSum       as Lang.Number = 0;
    var _windowPowerSum    as Lang.Number = 0;
    var _windowSampleCount as Lang.Number = 0;

    // Rolling 10-window buffer for live EF (post-lock)
    var _rollingHR    as Lang.Array<Lang.Float or Null>;
    var _rollingPower as Lang.Array<Lang.Float or Null>;
    var _rollingIdx   as Lang.Number = 0;
    var _rollingCount as Lang.Number = 0;

    var _currentDrift as Lang.Float  = 0.0;
    // True once we have a real drift value to show — either restored from
    // storage on resume, or written from the rolling EF after the buffer
    // reached ROLLING_MIN_DISPLAY windows. Lock alone is NOT enough: a
    // freshly locked baseline with an empty rolling buffer would otherwise
    // flash a false "0%" before any rolling data exists.
    var _hasDisplayValue as Lang.Boolean = false;
    var _saveCounter  as Lang.Number = 0;

    // Ticks since last gate-passing sample. Used to clear the rolling
    // buffer after long stops/coasts so the live EF doesn't stitch across
    // non-contiguous efforts.
    var _gateGapTicks as Lang.Number = 0;

    function initialize(hrRest as Lang.Number, cp as Lang.Number) {
        setConfig(hrRest, cp);

        _rollingHR    = new [ROLLING_WINDOWS];
        _rollingPower = new [ROLLING_WINDOWS];
        for (var i = 0; i < ROLLING_WINDOWS; i++) {
            _rollingHR[i]    = 0.0;
            _rollingPower[i] = 0.0;
        }
        _rollPwrBuf = new [POWER_ROLL_SECONDS];
        for (var i = 0; i < POWER_ROLL_SECONDS; i++) {
            _rollPwrBuf[i] = 0;
        }
    }

    // Called once at activity start. Resume baseline + last drift if within
    // the same 5 AM → 5 AM local window, otherwise start fresh.
    function onActivityStart() as Void {
        var now = Time.now();
        var g = Gregorian.info(now, Time.FORMAT_SHORT);
        var opts = {
            :year   => g.year,
            :month  => g.month,
            :day    => g.day,
            :hour   => 5,
            :minute => 0,
            :second => 0
        };
        var today5am = Gregorian.moment(opts);
        var boundary = today5am.value();
        if (now.value() < today5am.value()) {
            boundary -= 86400;  // yesterday 5 AM if it's pre-dawn
        }

        var lastUpdate  = Application.Storage.getValue(STORAGE_LAST_UPDATE);
        var storedBase  = Application.Storage.getValue(STORAGE_BASELINE);
        var storedLock  = Application.Storage.getValue(STORAGE_LOCKED);
        var storedDrift = Application.Storage.getValue(STORAGE_LAST_DRIFT);

        if (lastUpdate != null && lastUpdate >= boundary
            && storedBase != null && storedLock != null && storedLock) {
            _baselineEF       = storedBase.toFloat();
            _baselineLocked   = true;
            _currentDrift     = (storedDrift != null) ? storedDrift.toFloat() : 0.0;
            _hasDisplayValue  = (storedDrift != null);
            _validWindowCount = BASELINE_WINDOWS;
        } else {
            _baselineEF       = 0.0;
            _baselineLocked   = false;
            _currentDrift     = 0.0;
            _hasDisplayValue  = false;
            _validWindowCount = 0;
            _baselineHRSum    = 0.0;
            _baselinePowerSum = 0.0;
        }

        // Reset per-activity transients regardless
        _windowHRSum       = 0;
        _windowPowerSum    = 0;
        _windowSampleCount = 0;
        _rollingIdx        = 0;
        _rollingCount      = 0;
        _saveCounter       = 0;

        // Clear the 30-sec rolling power buffer — must refill before any
        // sample passes the validity gate again
        for (var i = 0; i < POWER_ROLL_SECONDS; i++) {
            _rollPwrBuf[i] = 0;
        }
        _rollPwrIdx   = 0;
        _rollPwrCount = 0;
        _rollPwrSum   = 0;

        _gateGapTicks = 0;
    }

    // Called every compute() tick (~1 Hz). Validity-gated: only seconds
    // where the 30-sec rolling power sits in the sustained-aerobic band
    // and HR is working contribute to baseline / drift computation.
    function update(hr as Lang.Number?, power as Lang.Number?) as Void {
        if (hr == null) { return; }

        // Maintain 30-sec rolling power. Null/coast counts as 0 here so the
        // average reflects actual recent effort.
        var p = (power == null) ? 0 : power;
        _rollPwrSum -= _rollPwrBuf[_rollPwrIdx];
        _rollPwrBuf[_rollPwrIdx] = p;
        _rollPwrSum += p;
        _rollPwrIdx = (_rollPwrIdx + 1) % POWER_ROLL_SECONDS;
        if (_rollPwrCount < POWER_ROLL_SECONDS) {
            _rollPwrCount += 1;
            return;  // can't gate until the 30-sec buffer is full
        }

        var rollPwr = _rollPwrSum.toFloat() / POWER_ROLL_SECONDS.toFloat();
        var gateFail =
            (rollPwr < _powerBandLow) || (rollPwr > _powerBandHigh)
            || (hr <= _hrRest + HR_FLOOR_MARGIN)
            || (power == null);

        if (gateFail) {
            // Track how long we've been outside the gate. After
            // GAP_RESET_SECONDS without a valid sample (long coast, stop,
            // technical descent), drop the rolling-EF buffer so the live
            // EF doesn't stitch across non-contiguous efforts.
            _gateGapTicks += 1;
            if (_gateGapTicks >= GAP_RESET_SECONDS && _rollingCount > 0) {
                _rollingCount = 0;
                _rollingIdx   = 0;
            }
            return;
        }

        _gateGapTicks = 0;

        _windowHRSum       += hr;
        _windowPowerSum    += power;
        _windowSampleCount += 1;

        if (_windowSampleCount >= WINDOW_SECONDS) {
            var windowHR    = _windowHRSum.toFloat()    / WINDOW_SECONDS.toFloat();
            var windowPower = _windowPowerSum.toFloat() / WINDOW_SECONDS.toFloat();

            if (!_baselineLocked) {
                _baselineHRSum    += windowHR;
                _baselinePowerSum += windowPower;
                _validWindowCount += 1;
                if (_validWindowCount >= BASELINE_WINDOWS) {
                    var avgHR    = _baselineHRSum    / BASELINE_WINDOWS.toFloat();
                    var avgPower = _baselinePowerSum / BASELINE_WINDOWS.toFloat();
                    if (avgHR > 0.0) {
                        _baselineEF     = avgPower / avgHR;
                        _baselineLocked = true;
                    }
                }
            } else {
                _rollingHR[_rollingIdx]    = windowHR;
                _rollingPower[_rollingIdx] = windowPower;
                _rollingIdx = (_rollingIdx + 1) % ROLLING_WINDOWS;
                if (_rollingCount < ROLLING_WINDOWS) {
                    _rollingCount += 1;
                }

                var rollHRSum    = 0.0;
                var rollPowerSum = 0.0;
                for (var i = 0; i < _rollingCount; i++) {
                    rollHRSum    += _rollingHR[i];
                    rollPowerSum += _rollingPower[i];
                }
                var rollHR    = rollHRSum    / _rollingCount.toFloat();
                var rollPower = rollPowerSum / _rollingCount.toFloat();
                if (rollHR > 0.0 && _baselineEF > 0.0
                    && _rollingCount >= ROLLING_MIN_DISPLAY) {
                    // Only overwrite the displayed drift once we have
                    // enough rolling windows for a stable signal. Before
                    // that, leave _currentDrift at its persisted value so
                    // a resume shows the rider's last drift, not a
                    // single-minute snapshot.
                    var currentEF = rollPower / rollHR;
                    if (currentEF > 0.0) {
                        _currentDrift    = (_baselineEF / currentEF) - 1.0;
                        _hasDisplayValue = true;
                    }
                }
            }

            _windowHRSum       = 0;
            _windowPowerSum    = 0;
            _windowSampleCount = 0;
        }

        _saveCounter += 1;
        if (_saveCounter >= SAVE_INTERVAL_TICKS) {
            saveNow();
            _saveCounter = 0;
        }
    }

    // Update runtime config (HRrest, CP) without disturbing baseline or
    // rolling buffers. Call from onSettingsChanged when user edits settings
    // mid-ride.
    function setConfig(hrRest as Lang.Number, cp as Lang.Number) as Void {
        _hrRest = hrRest;
        _cp     = cp;
        _powerBandLow  = cp.toFloat() * POWER_BAND_LOW_FRAC;
        _powerBandHigh = cp.toFloat() * POWER_BAND_HIGH_FRAC;
    }

    function saveNow() as Void {
        Application.Storage.setValue(STORAGE_BASELINE,    _baselineEF);
        Application.Storage.setValue(STORAGE_LOCKED,      _baselineLocked);
        Application.Storage.setValue(STORAGE_LAST_DRIFT,  _currentDrift);
        Application.Storage.setValue(STORAGE_LAST_UPDATE, Time.now().value());
    }

    function getDriftPercent() as Lang.Number {
        return (_currentDrift * 100.0).toNumber();
    }

    // True once the baseline is locked. Use in combination with
    // hasDisplayValue() to decide whether to render a drift number or "--".
    function isLocked() as Lang.Boolean {
        return _baselineLocked;
    }

    // True once we have a real drift to show — either a persisted value
    // restored on resume, or a rolling EF written after the buffer reached
    // ROLLING_MIN_DISPLAY. A freshly locked baseline with an empty rolling
    // buffer reports false, so the view shows "--" rather than a false 0%.
    function hasDisplayValue() as Lang.Boolean {
        return _hasDisplayValue;
    }
}
