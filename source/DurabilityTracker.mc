import Toybox.Application;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

// ─────────────────────────────────────────────────────────────────────────────
//  DurabilityTracker — cumulative kJ of work done in the current event-day,
//  used to modulate effective CP and W' as the rider fatigues.
//
//  Science (durability literature, Spragg/Maunder/Clark/Pugh 2018–2024):
//    Trained cyclists lose ~5% CP per 2,500 kJ of accumulated work, ~2% W'.
//    Amateurs lose more. We use the trained-cyclist coefficients as a
//    conservative starting point.
//
//      CP_effective  = CP  × (1 − 0.020 × kJ_total/1000)
//      W'_effective  = W'  × (1 − 0.008 × kJ_total/1000)
//
//    Floored at 0.7× to prevent absurd values past published data.
//
//  Persistence: same 5 AM local reset pattern as EFDriftTracker. All work
//  done between 5 AM and the next 5 AM accumulates into one durability
//  budget.
// ─────────────────────────────────────────────────────────────────────────────

class DurabilityTracker {

    const STORAGE_KJ          = "durabilityKJ";
    const STORAGE_LAST_UPDATE = "durabilityLastUpdate";

    const SAVE_INTERVAL_TICKS = 60;
    const CP_DECAY_PER_KJ     = 0.000020;  // 2.0% per 1000 kJ
    const W_DECAY_PER_KJ      = 0.000008;  // 0.8% per 1000 kJ
    const SCALE_FLOOR         = 0.70;      // sanity cap, beyond published data

    var _cumulativeKJ as Lang.Float  = 0.0;
    var _saveCounter  as Lang.Number = 0;

    function initialize() {
    }

    // Called once at activity start. Resume cumulative kJ if within the same
    // 5 AM → 5 AM local window, otherwise reset to 0.
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
            boundary -= 86400;
        }

        var lastUpdate = Application.Storage.getValue(STORAGE_LAST_UPDATE);
        var storedKJ   = Application.Storage.getValue(STORAGE_KJ);

        if (lastUpdate != null && storedKJ != null && lastUpdate >= boundary) {
            _cumulativeKJ = storedKJ.toFloat();
        } else {
            _cumulativeKJ = 0.0;
        }
        _saveCounter = 0;
    }

    // Called every compute() tick (~1 Hz). Accumulates work in kJ.
    // No-op if power is null or non-positive (coasting doesn't add fatigue).
    function update(power as Lang.Number?) as Void {
        if (power == null || power <= 0) { return; }
        _cumulativeKJ += power.toFloat() / 1000.0;

        _saveCounter += 1;
        if (_saveCounter >= SAVE_INTERVAL_TICKS) {
            saveNow();
            _saveCounter = 0;
        }
    }

    function saveNow() as Void {
        Application.Storage.setValue(STORAGE_KJ,          _cumulativeKJ);
        Application.Storage.setValue(STORAGE_LAST_UPDATE, Time.now().value());
    }

    function getCumulativeKJ() as Lang.Float {
        return _cumulativeKJ;
    }

    // Multiplier for fresh CP. 1.0 = fresh, decreases as kJ accumulate.
    function getCpScale() as Lang.Float {
        var scale = 1.0 - CP_DECAY_PER_KJ * _cumulativeKJ;
        if (scale < SCALE_FLOOR) { scale = SCALE_FLOOR; }
        return scale;
    }

    // Multiplier for fresh W'. 1.0 = fresh, decreases as kJ accumulate.
    function getWPrimeScale() as Lang.Float {
        var scale = 1.0 - W_DECAY_PER_KJ * _cumulativeKJ;
        if (scale < SCALE_FLOOR) { scale = SCALE_FLOOR; }
        return scale;
    }
}
