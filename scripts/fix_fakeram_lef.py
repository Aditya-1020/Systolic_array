#!/usr/bin/env python3
# Fixes sky130 fakeram LEF obstruction layers
import re
import sys

BLOCK = ("met1", "met2")

def fix(text):
    m = re.search(r"SIZE\s+([\d.]+)\s+BY\s+([\d.]+)\s*;", text)
    if not m:
        raise SystemExit("no SIZE statement")
    w, h = m.group(1), m.group(2)
    out, in_obs, skip, seen = [], False, False, set()
    for ln in text.splitlines():
        t = ln.strip()
        if t == "OBS":
            in_obs, seen = True, set()
        if in_obs:
            lm = re.match(r"LAYER\s+(\S+)\s*;", t)
            if lm:
                skip = lm.group(1) == "OVERLAP"
                if not skip:
                    seen.add(lm.group(1))
            if skip and not lm:
                if t == "END":
                    skip, in_obs = False, False
                    out += add_missing(seen, w, h)
                    out.append(ln)
                continue
            if skip:
                continue
            if t == "END":
                in_obs = False
                out += add_missing(seen, w, h)
        out.append(ln)
    return "\n".join(out) + "\n"

def add_missing(seen, w, h):
    r = []
    for l in BLOCK:
        if l not in seen:
            r += [f"    LAYER {l} ;", f"    RECT 0 0 {w} {h} ;"]
    return r

for p in sys.argv[1:]:
    s = open(p).read()
    if "OVERLAP" not in s and all(f"LAYER {l}" in s for l in BLOCK):
        print(f"{p}: already ok")
        continue
    open(p, "w").write(fix(s))
    print(f"{p}: fixed")