import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;
import Toybox.Time.Gregorian;

// ─────────────────────────────────────────────────────────────────────────────
//  StrainTracker — Whoop-style cumulative cardiovascular load, 0–21 scale.
//
//  TRIMP (Banister):   HRR × 0.64 × e^(1.92·HRR)  [per minute]
//  HRR:                (HR − HRrest) / (HRmax − HRrest), clamped to [0, 1]
//  Strain mapping:     21 × (1 − e^(−TRIMP / K)),  K configurable
//
//  Event accumulation persists across activity stop/start, power-off, and
//  reboot via Application.Storage. Resets at 6 AM local time: if the last
//  stored update is older than the most recent 6 AM boundary, start fresh.
// ─────────────────────────────────────────────────────────────────────────────

class StrainTracker {

    const STORAGE_TRIMP      = "strainTrimp";
    const STORAGE_LAST_UPDATE = "strainLastUpdate";
    const SAVE_INTERVAL_TICKS = 60;
    // Connect IQ's Math module lacks exp(); use pow(E, x) instead.
    const E = 2.718281828459045;

    var _hrRest         as Lang.Number = 52;
    var _hrMax          as Lang.Number = 174;
    var _strainK        as Lang.Number = 60;
    var _eventTrimp     as Lang.Float  = 0.0;
    var _rideStartTrimp as Lang.Float  = 0.0;
    var _saveCounter    as Lang.Number = 0;

    function initialize(hrRest as Lang.Number, hrMax as Lang.Number,
                        strainK as Lang.Number) {
        _hrRest  = hrRest;
        _hrMax   = hrMax;
        _strainK = (strainK > 0) ? strainK : 1;
    }

    // Called once at activity start. Resume from storage if within same
    // 6 AM → 6 AM local window, otherwise reset to 0.
    function onActivityStart() as Void {
        var now = Time.now();
        var g = Gregorian.info(now, Time.FORMAT_SHORT);
        var opts = {
            :year   => g.year,
            :month  => g.month,
            :day    => g.day,
            :hour   => 6,
            :minute => 0,
            :second => 0
        };
        var today6am = Gregorian.moment(opts);
        var boundary = today6am.value();
        if (now.value() < today6am.value()) {
            boundary -= 86400;  // use yesterday 6 AM if it's pre-dawn
        }

        var lastUpdate  = Application.Storage.getValue(STORAGE_LAST_UPDATE);
        var storedTrimp = Application.Storage.getValue(STORAGE_TRIMP);

        if (lastUpdate != null && storedTrimp != null && lastUpdate >= boundary) {
            _eventTrimp = storedTrimp.toFloat();
        } else {
            _eventTrimp = 0.0;
        }
        _rideStartTrimp = _eventTrimp;
        _saveCounter = 0;
    }

    // Called every compute() tick (~1 Hz). No-op if HR is null or at/below rest.
    function update(hr as Lang.Number?) as Void {
        if (hr == null || hr <= _hrRest) { return; }
        var range = (_hrMax - _hrRest).toFloat();
        if (range <= 0.0) { return; }

        var hrr = (hr - _hrRest).toFloat() / range;
        if (hrr > 1.0) { hrr = 1.0; }

        // Banister per-minute TRIMP → per-second by /60
        var delta = hrr * 0.64 * Math.pow(E, 1.92 * hrr) / 60.0;
        _eventTrimp += delta;

        _saveCounter += 1;
        if (_saveCounter >= SAVE_INTERVAL_TICKS) {
            saveNow();
            _saveCounter = 0;
        }
    }

    function saveNow() as Void {
        Application.Storage.setValue(STORAGE_TRIMP, _eventTrimp);
        Application.Storage.setValue(STORAGE_LAST_UPDATE, Time.now().value());
    }

    function getCumulative() as Lang.Number {
        return strainFromTrimp(_eventTrimp).toNumber();
    }

    function getRideDelta() as Lang.Number {
        var delta = strainFromTrimp(_eventTrimp) - strainFromTrimp(_rideStartTrimp);
        if (delta < 0.0) { delta = 0.0; }
        return delta.toNumber();
    }

    private function strainFromTrimp(trimp as Lang.Float) as Lang.Float {
        return 21.0 * (1.0 - Math.pow(E, -trimp / _strainK.toFloat()));
    }
}
