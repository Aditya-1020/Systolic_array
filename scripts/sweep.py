#!/usr/bin/env python3
"""Macro placement sweep: generate TCLs -> run ORFS in batches -> aggregate metrics.
Lives in scripts/. Drives the project Makefile (`make flow`), one FLOW_VARIANT per placement.

  scripts/sweep.py gen
  scripts/sweep.py run -j 3                       # all layouts, 3 at a time
  scripts/sweep.py run --only tl_2x2,corners,auto_rtlmp -j 2
  scripts/sweep.py run -j 3 --extra "SDC_FILE=$PWD/constraints/constraints.sdc"
  scripts/sweep.py agg                            # re-aggregate only
  scripts/sweep.py agg --list-keys                # metric names in the first report found

Placement TCLs go to design-configs/macro_place/sweep/, logs and summary.csv to orfs-out/sweep/.
`auto_rtlmp` runs with no MACRO_PLACEMENT_TCL (ORFS automatic placer) as the baseline.
"""
import argparse, csv, json, os, shlex, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent      # project root (scripts/..)
OUT = ROOT / "orfs-out"                             # WORK_HOME in the Makefile
PLC = ROOT / "design-configs" / "macro_place" / "sweep"
SWEEP = OUT / "sweep"

# ---- design constants (macro size from the fakeram130_128x64 LEF) ------------
W, H = 191.82, 329.12
CORE = (10, 10, 1460, 760)          # llx lly urx ury, same as CORE_AREA in systolic.mk
GAP = 20                            # min spacing: macro-macro and macro-core edge
MACROS = [                          # row-major order used by the layouts below
    "inst_acc_buf.gen_half\\[0\\].u_fakeram",
    "inst_acc_buf.gen_half\\[1\\].u_fakeram",
    "inst_res_buf.gen_half\\[0\\].u_fakeram",
    "inst_res_buf.gen_half\\[1\\].u_fakeram",
]

XL, XR = CORE[0] + GAP, CORE[2] - GAP - W
YB, YT = CORE[1] + GAP, CORE[3] - GAP - H
PX, PY = W + GAP, H + GAP


def grid(cols, rows, h="l", v="b"):
    """cols x rows block anchored to a core corner (h: l/r, v: b/t); row 0 is the top row."""
    pos = []
    for r in range(rows):
        for c in range(cols):
            x = XL + c * PX if h == "l" else XR - (cols - 1 - c) * PX
            y = YT - r * PY if v == "t" else YB + (rows - 1 - r) * PY
            pos.append((x, y))
    return pos


LAYOUTS = {
    "tl_2x2": grid(2, 2, "l", "t"),
    "tr_2x2": grid(2, 2, "r", "t"),
    "bl_2x2": grid(2, 2, "l", "b"),
    "br_2x2": grid(2, 2, "r", "b"),
    "row_bottom": grid(4, 1, "l", "b"),
    "row_top": grid(4, 1, "l", "t"),
    "split_lr": grid(1, 2, "l", "b") + grid(1, 2, "r", "b"),   # acc pair left, res pair right
    "split_tb": grid(2, 1, "l", "t") + grid(2, 1, "l", "b"),   # acc pair top, res pair bottom
    "corners": [(XL, YT), (XR, YT), (XL, YB), (XR, YB)],
    "auto_rtlmp": None,                                         # baseline: no TCL
}

# (column name, metric key). Missing keys print as NA; use `agg --list-keys` to fix names.
KEYS = [
    ("gpl_ws", "globalplace__timing__setup__ws"),
    ("cts_ws", "cts__timing__setup__ws"),
    ("grt_ws", "globalroute__timing__setup__ws"),
    ("ws", "finish__timing__setup__ws"),
    ("tns", "finish__timing__setup__tns"),
    ("wl_um", "detailedroute__route__wirelength"),
    ("drc", "detailedroute__route__drc_errors"),
    ("max_slew", "finish__timing__drv__max_slew"),
    ("max_cap", "finish__timing__drv__max_cap"),
    ("util", "finish__design__instance__utilization"),
    ("power", "finish__power__total"),
]


def check(name, pos):
    """Reject placements that leave the core or break spacing."""
    boxes = [(x, y, x + W, y + H) for x, y in pos]
    for n, (a, b, c, d) in zip(MACROS, boxes):
        if a < CORE[0] + GAP - 1e-6 or b < CORE[1] + GAP - 1e-6 \
           or c > CORE[2] - GAP + 1e-6 or d > CORE[3] - GAP + 1e-6:
            sys.exit(f"{name}: {n} outside core+margin: {(a, b, c, d)}")
    for i in range(len(boxes)):
        for j in range(i + 1, len(boxes)):
            a, b, c, d = boxes[i]
            e, f, g, h = boxes[j]
            if not (e >= c + GAP - 1e-6 or g <= a - GAP + 1e-6 or
                    f >= d + GAP - 1e-6 or h <= b - GAP + 1e-6):
                sys.exit(f"{name}: {MACROS[i]} and {MACROS[j]} closer than {GAP} um")


def gen(names):
    plc = PLC
    plc.mkdir(parents=True, exist_ok=True)
    for name in names:
        pos = LAYOUTS[name]
        if pos is None:
            continue
        check(name, pos)
        lines = [f"place_macro -macro_name {{{m}}} -location {{{x:.2f} {y:.2f}}} -orientation R0"
                 for m, (x, y) in zip(MACROS, pos)]
        (plc / f"{name}.tcl").write_text("\n".join(lines) + "\n")
    print(f"generated {len([n for n in names if LAYOUTS[n]])} placements in {plc}")


def find_report(variant):
    for p in OUT.rglob("6_report.json"):
        if p.parent.name == variant:
            return p
    return None


def load_metrics(variant):
    """6_report.json if the run finished, else merge whatever per-stage JSONs exist."""
    p = find_report(variant)
    if p:
        return json.loads(p.read_text()), "yes"
    dirs = [d for d in OUT.glob(f"logs/*/*/{variant}") if d.is_dir()]
    merged = {}
    for f in sorted(dirs[0].glob("*.json")) if dirs else []:
        try:
            merged.update(json.loads(f.read_text()))
        except ValueError:
            pass
    return (merged, "no") if merged else (None, "no")


def run_one(name, a):
    variant = f"mp_{name}"
    if not a.force and find_report(variant):
        return name, "skipped (report exists)"
    (SWEEP / "logs").mkdir(parents=True, exist_ok=True)
    cmd = ["make", "-C", str(ROOT), "flow", f"DESIGN={a.design}", f"FLOW_VARIANT={variant}",
           f"NUM_CORES={a.cores}", f"STOP={a.stop}"] + shlex.split(a.extra)
    if LAYOUTS[name] is not None:
        cmd.append(f"MACRO_PLACEMENT_TCL={PLC / (name + '.tcl')}")
    with open(SWEEP / "logs" / f"{variant}.log", "w") as log:
        rc = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT).returncode
    return name, "ok" if rc == 0 else f"FAILED rc={rc} (see orfs-out/sweep/logs/{variant}.log)"


def run(a, names):
    gen(names)
    a.cores = a.cores or max(1, (os.cpu_count() or 2) // a.jobs)
    print(f"{len(names)} runs, {a.jobs} at a time, {a.cores} cores each")
    with ThreadPoolExecutor(max_workers=a.jobs) as ex:
        for name, status in ex.map(lambda n: run_one(n, a), names):
            print(f"  {name:12s} {status}")


def fmt(v):
    if v is None:
        return "NA"
    return f"{v:.4g}" if isinstance(v, float) else str(v)


def best_ws(r):
    for k in ("ws", "grt_ws", "cts_ws", "gpl_ws"):
        if isinstance(r[k], (int, float)):
            return r[k]
    return float("-inf")


def agg(a, names):
    rows = []
    for name in names:
        d, done = load_metrics(f"mp_{name}")
        if d is None:
            continue
        if a.list_keys:
            print("\n".join(sorted(d)))
            return
        rows.append({"placement": name, "finished": done, **{col: d.get(key) for col, key in KEYS}})
    if not rows:
        print("no reports found")
        return
    rows.sort(key=best_ws, reverse=True)
    cols = ["placement", "finished"] + [c for c, _ in KEYS]
    SWEEP.mkdir(parents=True, exist_ok=True)
    with open(SWEEP / "summary.csv", "w", newline="") as f:
        w = csv.DictWriter(f, cols)
        w.writeheader()
        w.writerows(rows)
    table = [cols] + [[fmt(r[c]) if c not in ("placement", "finished") else r[c] for c in cols] for r in rows]
    width = [max(len(row[i]) for row in table) for i in range(len(cols))]
    for row in table:
        print("  ".join(c.ljust(w) for c, w in zip(row, width)))
    print(f"\nwritten {SWEEP / 'summary.csv'} (sorted by latest setup ws available, best first; "
          "finished=no means the run died before the final report, so later columns are NA)")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("cmd", choices=["gen", "run", "agg"])
    ap.add_argument("--design", default="systolic", help="DESIGN= for the Makefile")
    ap.add_argument("--stop", default="cts", help="ORFS stage to stop at: synth|floorplan|place|cts|grt|route|finish")
    ap.add_argument("--extra", default="", help='extra make args, e.g. "SDC_FILE=/abs/x.sdc"')
    ap.add_argument("-j", "--jobs", type=int, default=2, help="runs in parallel")
    ap.add_argument("--cores", type=int, default=0, help="NUM_CORES per run (default: cpus / jobs)")
    ap.add_argument("--only", default="", help="comma-separated placement names")
    ap.add_argument("--force", action="store_true", help="rerun even if a report exists")
    ap.add_argument("--list-keys", action="store_true")
    a = ap.parse_args()

    SWEEP.mkdir(parents=True, exist_ok=True)
    names = [n for n in a.only.split(",") if n] or list(LAYOUTS)
    bad = [n for n in names if n not in LAYOUTS]
    if bad:
        sys.exit(f"unknown placement(s): {bad}; choose from {list(LAYOUTS)}")
    if a.cmd == "gen":
        gen(names)
    elif a.cmd == "run":
        run(a, names)
        agg(a, names)
    else:
        agg(a, names)


if __name__ == "__main__":
    main()
