#!/usr/bin/env python3
"""
eval-rides.py — replay the current EFDriftTracker + DurabilityTracker algorithm
over a folder of FIT files and report stability metrics.

This is a faithful Python port of source/EFDriftTracker.mc and
source/DurabilityTracker.mc (the in-car JD pacing algorithm) so we can
validate the current gate/smoothing constants against the full ride library
without flashing the watch sim against each file.

Key metric: per-window drift jitter — the mean absolute minute-to-minute change
in the EF-drift signal. Lower = steadier number on the rider's screen.
We report BOTH:
  - raw  : single 1-min window EF vs baseline (no rolling smoothing)
  - rolled: the current 10-min rolling drift the field actually displays
"""

import sys
import glob
import os
import statistics
from fitparse import FitFile

# ---- config: mirrors resources/properties.xml defaults --------------------
HR_REST = 52
CP = 171
W_PRIME = 20000

# ---- EFDriftTracker constants (verbatim from the .mc) ---------------------
HR_FLOOR_MARGIN = 20
WINDOW_SECONDS = 60
BASELINE_WINDOWS = 10   # shipped value (was 15); see EFDriftTracker.mc
ROLLING_WINDOWS = 10
ROLLING_MIN_DISPLAY = 5
POWER_ROLL_SECONDS = 30
POWER_BAND_LOW_FRAC = 0.55
POWER_BAND_HIGH_FRAC = 1.05
GAP_RESET_SECONDS = 120

# ---- DurabilityTracker constants ------------------------------------------
CP_DECAY_PER_KJ = 0.000020
W_DECAY_PER_KJ = 0.000008
SCALE_FLOOR = 0.70


class EFDrift:
    # baseline_windows  : valid 1-min windows needed to lock (current = 15)
    # base_band_low_frac: low edge of the gate WHILE accumulating the baseline
    #                     only; once locked the gate reverts to the standard
    #                     POWER_BAND_LOW_FRAC so the displayed drift keeps its
    #                     validated 0.55-1.05 band and jitter profile.
    def __init__(self, hr_rest=HR_REST, cp=CP,
                 baseline_windows=BASELINE_WINDOWS,
                 base_band_low_frac=POWER_BAND_LOW_FRAC):
        self.hr_rest = hr_rest
        self.cp = cp
        self.baseline_windows = baseline_windows
        self.band_low = cp * POWER_BAND_LOW_FRAC
        self.band_low_base = cp * base_band_low_frac
        self.band_high = cp * POWER_BAND_HIGH_FRAC

        self.roll_pwr = [0] * POWER_ROLL_SECONDS
        self.roll_pwr_idx = 0
        self.roll_pwr_count = 0
        self.roll_pwr_sum = 0

        self.baseline_ef = 0.0
        self.locked = False
        self.valid_windows = 0
        self.base_hr_sum = 0.0
        self.base_pwr_sum = 0.0

        self.win_hr_sum = 0
        self.win_pwr_sum = 0
        self.win_count = 0

        self.rolling_hr = [0.0] * ROLLING_WINDOWS
        self.rolling_pwr = [0.0] * ROLLING_WINDOWS
        self.rolling_idx = 0
        self.rolling_count = 0

        self.current_drift = 0.0
        self.has_display = False
        self.gap_ticks = 0

        # instrumentation (not in .mc)
        self.lock_tick = None       # tick index at which baseline locked
        self.raw_series = []        # per-window single-min drift %
        self.rolled_series = []     # displayed rolling drift % (post-display)

    def update(self, tick, hr, power):
        if hr is None:
            return
        p = 0 if power is None else power
        self.roll_pwr_sum -= self.roll_pwr[self.roll_pwr_idx]
        self.roll_pwr[self.roll_pwr_idx] = p
        self.roll_pwr_sum += p
        self.roll_pwr_idx = (self.roll_pwr_idx + 1) % POWER_ROLL_SECONDS
        if self.roll_pwr_count < POWER_ROLL_SECONDS:
            self.roll_pwr_count += 1
            return

        roll_pwr = self.roll_pwr_sum / POWER_ROLL_SECONDS
        low_edge = self.band_low if self.locked else self.band_low_base
        gate_fail = (
            roll_pwr < low_edge
            or roll_pwr > self.band_high
            or hr <= self.hr_rest + HR_FLOOR_MARGIN
            or power is None
        )
        if gate_fail:
            self.gap_ticks += 1
            if self.gap_ticks >= GAP_RESET_SECONDS and self.rolling_count > 0:
                self.rolling_count = 0
                self.rolling_idx = 0
            return
        self.gap_ticks = 0

        self.win_hr_sum += hr
        self.win_pwr_sum += power
        self.win_count += 1

        if self.win_count >= WINDOW_SECONDS:
            win_hr = self.win_hr_sum / WINDOW_SECONDS
            win_pwr = self.win_pwr_sum / WINDOW_SECONDS

            if not self.locked:
                self.base_hr_sum += win_hr
                self.base_pwr_sum += win_pwr
                self.valid_windows += 1
                if self.valid_windows >= self.baseline_windows:
                    avg_hr = self.base_hr_sum / self.baseline_windows
                    avg_pwr = self.base_pwr_sum / self.baseline_windows
                    if avg_hr > 0.0:
                        self.baseline_ef = avg_pwr / avg_hr
                        self.locked = True
                        self.lock_tick = tick
            else:
                # raw single-minute drift (for jitter comparison)
                if win_hr > 0 and self.baseline_ef > 0:
                    raw_ef = win_pwr / win_hr
                    if raw_ef > 0:
                        self.raw_series.append(
                            ((self.baseline_ef / raw_ef) - 1.0) * 100.0)

                self.rolling_hr[self.rolling_idx] = win_hr
                self.rolling_pwr[self.rolling_idx] = win_pwr
                self.rolling_idx = (self.rolling_idx + 1) % ROLLING_WINDOWS
                if self.rolling_count < ROLLING_WINDOWS:
                    self.rolling_count += 1

                roll_hr = sum(self.rolling_hr[:self.rolling_count]) / self.rolling_count
                roll_pw = sum(self.rolling_pwr[:self.rolling_count]) / self.rolling_count
                if (roll_hr > 0 and self.baseline_ef > 0
                        and self.rolling_count >= ROLLING_MIN_DISPLAY):
                    cur_ef = roll_pw / roll_hr
                    if cur_ef > 0:
                        self.current_drift = (self.baseline_ef / cur_ef) - 1.0
                        self.has_display = True
                        self.rolled_series.append(self.current_drift * 100.0)

            self.win_hr_sum = 0
            self.win_pwr_sum = 0
            self.win_count = 0


def jitter(series):
    """Mean absolute successive difference of a series (display stability)."""
    if len(series) < 2:
        return None
    diffs = [abs(series[i] - series[i - 1]) for i in range(1, len(series))]
    return statistics.mean(diffs)


_REC_CACHE = {}


def parse_ride(path):
    """Return [(hr, power), ...] once per file; cached for sweeps."""
    if path in _REC_CACHE:
        return _REC_CACHE[path]
    recs = []
    for rec in FitFile(path).get_messages("record"):
        d = {f.name: f.value for f in rec}
        recs.append((d.get("heart_rate"), d.get("power")))
    _REC_CACHE[path] = recs
    return recs


def eval_ride(path, baseline_windows=BASELINE_WINDOWS,
              base_band_low_frac=POWER_BAND_LOW_FRAC):
    ef = EFDrift(baseline_windows=baseline_windows,
                 base_band_low_frac=base_band_low_frac)
    kj = 0.0
    tick = 0
    pwr_vals, hr_vals = [], []
    for hr, power in parse_ride(path):
        ef.update(tick, hr, power)
        if power is not None and power > 0:
            kj += power / 1000.0
            pwr_vals.append(power)
        if hr is not None:
            hr_vals.append(hr)
        tick += 1

    cp_scale = max(SCALE_FLOOR, 1.0 - CP_DECAY_PER_KJ * kj)
    w_scale = max(SCALE_FLOOR, 1.0 - W_DECAY_PER_KJ * kj)

    return {
        "file": os.path.basename(path),
        "secs": tick,
        "has_power": len(pwr_vals) > 0,
        "avg_pwr": statistics.mean(pwr_vals) if pwr_vals else 0,
        "avg_hr": statistics.mean(hr_vals) if hr_vals else 0,
        "kj": kj,
        "locked": ef.locked,
        "lock_min": (ef.lock_tick / 60.0) if ef.lock_tick is not None else None,
        "n_disp": len(ef.rolled_series),
        "final_drift": ef.current_drift * 100.0 if ef.has_display else None,
        "raw_jitter": jitter(ef.raw_series),
        "rolled_jitter": jitter(ef.rolled_series),
        "cp_eff": CP * cp_scale,
        "w_eff": W_PRIME * w_scale,
    }


def aggregate(files, bw, blow):
    """Run one parameter combo over all files; return summary dict."""
    rows = []
    for f in files:
        try:
            rows.append(eval_ride(f, baseline_windows=bw, base_band_low_frac=blow))
        except Exception:
            pass
    powered = [r for r in rows if r["has_power"]]
    locked = [r for r in powered if r["locked"]]
    displayed = [r for r in locked if r["final_drift"] is not None]
    lockmins = [r["lock_min"] for r in locked]
    rollj = [r["rolled_jitter"] for r in displayed if r["rolled_jitter"] is not None]
    return {
        "powered": len(powered),
        "locked": len(locked),
        "displayed": len(displayed),
        "lock_med": statistics.median(lockmins) if lockmins else None,
        "lock_max": max(lockmins) if lockmins else None,
        "jit_med": statistics.median(rollj) if rollj else None,
        "jit_max": max(rollj) if rollj else None,
    }


def sweep(folder):
    files = sorted(glob.glob(os.path.join(folder, "*.fit")))
    # (label, baseline_windows, baseline-phase low band frac)
    combos = [
        ("current  BW=15 low=0.55", 15, 0.55),
        ("BW=10     low=0.55",      10, 0.55),
        ("BW=15     low=0.50",      15, 0.50),
        ("BW=10     low=0.50",      10, 0.50),
        ("BW=10     low=0.45",      10, 0.45),
    ]
    hdr = (f"{'variant':<26}{'lock/pwr':>9}{'disp':>6}"
           f"{'lockMed':>9}{'lockMax':>9}{'jitMed':>8}{'jitMax':>8}")
    print(hdr)
    print("-" * len(hdr))
    for label, bw, blow in combos:
        s = aggregate(files, bw, blow)
        lm = f"{s['lock_med']:.0f}" if s['lock_med'] is not None else "--"
        lx = f"{s['lock_max']:.0f}" if s['lock_max'] is not None else "--"
        jm = f"{s['jit_med']:.2f}" if s['jit_med'] is not None else "--"
        jx = f"{s['jit_max']:.2f}" if s['jit_max'] is not None else "--"
        print(f"{label:<26}{str(s['locked'])+'/'+str(s['powered']):>9}"
              f"{s['displayed']:>6}{lm:>9}{lx:>9}{jm:>8}{jx:>8}")
    print("-" * len(hdr))
    print("lock/pwr = rides locking baseline / rides with power")
    print("disp     = rides that produced a displayed drift number")
    print("lockMed/Max = time-to-lock minutes;  jit = rolled drift jitter %")


def main():
    paths = [a for a in sys.argv[1:] if not a.startswith("--")]
    folder = paths[0] if paths else os.path.expanduser("~/Desktop/rides")
    if "--sweep" in sys.argv:
        sweep(folder)
        return
    files = sorted(glob.glob(os.path.join(folder, "*.fit")))
    if not files:
        print(f"no .fit files in {folder}")
        return

    rows = []
    for f in files:
        try:
            rows.append(eval_ride(f))
        except Exception as e:
            print(f"  !! {os.path.basename(f)}: {e}", file=sys.stderr)

    hdr = (f"{'file':<26}{'min':>5}{'avgP':>5}{'avgHR':>6}{'kJ':>6}"
           f"{'lock@':>7}{'disp':>5}{'drift%':>7}{'rawJ':>6}{'rollJ':>7}")
    print(hdr)
    print("-" * len(hdr))

    powered = [r for r in rows if r["has_power"]]
    locked = [r for r in powered if r["locked"]]
    displayed = [r for r in locked if r["final_drift"] is not None]

    for r in rows:
        lk = f"{r['lock_min']:.1f}" if r["lock_min"] is not None else "--"
        dr = f"{r['final_drift']:+.1f}" if r["final_drift"] is not None else "--"
        rj = f"{r['raw_jitter']:.1f}" if r["raw_jitter"] is not None else "--"
        rlj = f"{r['rolled_jitter']:.2f}" if r["rolled_jitter"] is not None else "--"
        print(f"{r['file']:<26}{r['secs']/60:>5.0f}{r['avg_pwr']:>5.0f}"
              f"{r['avg_hr']:>6.0f}{r['kj']:>6.0f}{lk:>7}{r['n_disp']:>5}"
              f"{dr:>7}{rj:>6}{rlj:>7}")

    print("-" * len(hdr))
    print(f"\nrides total            : {len(rows)}")
    print(f"with power             : {len(powered)}")
    print(f"baseline locked        : {len(locked)}  "
          f"({100*len(locked)/len(powered):.0f}% of powered)" if powered else "")
    print(f"produced display drift : {len(displayed)}")
    if displayed:
        rawj = [r["raw_jitter"] for r in displayed if r["raw_jitter"] is not None]
        rollj = [r["rolled_jitter"] for r in displayed if r["rolled_jitter"] is not None]
        lockmins = [r["lock_min"] for r in displayed]
        print(f"\njitter (mean |Δ| minute-to-minute drift %):")
        if rawj:
            print(f"  raw single-min : median {statistics.median(rawj):.1f}%  "
                  f"range {min(rawj):.1f}–{max(rawj):.1f}%")
        if rollj:
            print(f"  rolled (shown) : median {statistics.median(rollj):.2f}%  "
                  f"range {min(rollj):.2f}–{max(rollj):.2f}%")
        print(f"\ntime-to-lock (min): median {statistics.median(lockmins):.1f}  "
              f"range {min(lockmins):.1f}–{max(lockmins):.1f}")


if __name__ == "__main__":
    main()
