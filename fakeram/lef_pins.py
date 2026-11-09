#!/usr/bin/env python3
import csv
import re
import sys
from pathlib import Path

def extract_pins(lef_path):
    text = Path(lef_path).read_text(errors="ignore")
    macro = re.search(r"\bMACRO\s+(\S+)(.*?)(?=\bEND\s+\1\b)", text, re.S)

    if not macro:
        raise ValueError("No MACRO found")

    macro_name, body = macro.groups()
    rows = []

    pin_pattern = re.compile(r"\bPIN\s+([^\s;]+)(.*?)(?=\bEND\s+\1\b)", re.S,)

    for match in pin_pattern.finditer(body):
        pin_name, pin_block = match.groups()
        if re.fullmatch(r".*\[\d+", pin_name):
            pin_name += "]"

        direction_match = re.search(r"\bDIRECTION\s+(\w+)\s*;", pin_block, re.I,)
        direction = direction_match.group(1).upper() if direction_match else ""

        for port_number, port in enumerate(re.findall(r"\bPORT\b(.*?)(?=\bEND\b)", pin_block, re.S), start=1,):
            layer_matches = re.finditer(r"\bLAYER\s+(\S+)\s*;(.*?)(?=\bLAYER\b|\Z)", port, re.S,)

            for layer_match in layer_matches:
                layer, geometry = layer_match.groups()
                rects = re.findall(r"\bRECT\s+([-+\d.eE]+)\s+([-+\d.eE]+)\s+" r"([-+\d.eE]+)\s+([-+\d.eE]+)\s*;", geometry,)

                for rect in rects:
                    rows.append([pin_name, direction, port_number, layer, *rect,])

    return macro_name, rows

def main():
    if len(sys.argv) != 2:
        raise SystemExit(f"Usage: {Path(sys.argv[0]).name} <lef_file>")

    lef_path = Path(sys.argv[1])
    macro_name, rows = extract_pins(lef_path)
    output_path = lef_path.with_suffix(".csv")

    fields = ["pin", "direction", "port", "layer", "rect_x1", "rect_y1", "rect_x2", "rect_y2"]

    with output_path.open("w", newline="") as output:
        writer = csv.writer(output)
        writer.writerow(fields)
        writer.writerows(rows)

    print(f"Macro: {macro_name}")
    print(f"Pins: {len({row[0] for row in rows})}")
    print(f"Rectangles: {len(rows)}")
    print(f"CSV: {output_path}")

if __name__ == "__main__":
    main()
