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
//  Baseline locks once 20 valid 1-min windows accumulate. A window is "valid"
//  when power > 50 W and HR > HRrest + 20 (filters out coasting on MTB).
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

    const POWER_FLOOR         = 50;
    const HR_FLOOR_MARGIN     = 20;
    const WINDOW_SECONDS      = 60;
    const BASELINE_WINDOWS    = 20;
    const ROLLING_WINDOWS     = 5;
    const SAVE_INTERVAL_TICKS = 60;

    var _hrRest as Lang.Number = 52;

    var _baselineEF       as Lang.Float   = 0.0;
    var _baselineLocked   as Lang.Boolean = false;
    var _validWindowCount as Lang.Number  = 0;
    var _baselineHRSum    as Lang.Float   = 0.0;
    var _baselinePowerSum as Lang.Float   = 0.0;

    // Current 1-min window accumulators
    var _windowHRSum       as Lang.Number = 0;
    var _windowPowerSum    as Lang.Number = 0;
    var _windowSampleCount as Lang.Number = 0;

    // Rolling 5-window buffer for live EF (post-lock)
    var _rollingHR    as Lang.Array<Lang.Float or Null>;
    var _rollingPower as Lang.Array<Lang.Float or Null>;
    var _rollingIdx   as Lang.Number = 0;
    var _rollingCount as Lang.Number = 0;

    var _currentDrift as Lang.Float  = 0.0;
    var _saveCounter  as Lang.Number = 0;

    function initialize(hrRest as Lang.Number) {
        _hrRest = hrRest;
        _rollingHR    = new [ROLLING_WINDOWS];
        _rollingPower = new [ROLLING_WINDOWS];
        for (var i = 0; i < ROLLING_WINDOWS; i++) {
            _rollingHR[i]    = 0.0;
            _rollingPower[i] = 0.0;
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
            _validWindowCount = BASELINE_WINDOWS;
        } else {
            _baselineEF       = 0.0;
            _baselineLocked   = false;
            _currentDrift     = 0.0;
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
    }

    // Called every compute() tick (~1 Hz). Validity-gated: nulls, coasting,
    // and below-working HR are ignored.
    function update(hr as Lang.Number?, power as Lang.Number?) as Void {
        if (hr == null || power == null) { return; }
        if (power <= POWER_FLOOR || hr <= _hrRest + HR_FLOOR_MARGIN) { return; }

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
                if (rollHR > 0.0 && _baselineEF > 0.0) {
                    var currentEF = rollPower / rollHR;
                    if (currentEF > 0.0) {
                        _currentDrift = (_baselineEF / currentEF) - 1.0;
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

    function saveNow() as Void {
        Application.Storage.setValue(STORAGE_BASELINE,    _baselineEF);
        Application.Storage.setValue(STORAGE_LOCKED,      _baselineLocked);
        Application.Storage.setValue(STORAGE_LAST_DRIFT,  _currentDrift);
        Application.Storage.setValue(STORAGE_LAST_UPDATE, Time.now().value());
    }

    function getDriftPercent() as Lang.Number {
        return (_currentDrift * 100.0).toNumber();
    }

    function isLocked() as Lang.Boolean {
        return _baselineLocked;
    }
}
