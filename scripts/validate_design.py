#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from pathlib import Path


def read_filelist(path: Path) -> list[Path]:
    sources: list[Path] = []
    for raw in path.read_text().splitlines():
        entry = raw.split("#", 1)[0].strip()
        if entry:
            source = (path.parent / entry).resolve()
            if not source.is_file():
                raise FileNotFoundError(f"filelist entry does not exist: {source}")
            sources.append(source)
    if not sources:
        raise ValueError(f"empty RTL filelist: {path}")
    return sources


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--platform", choices=("sky130hd", "nangate45"), required=True)
    parser.add_argument("--design-config", type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    config = args.design_config if args.design_config.is_absolute() else root / args.design_config

    if not config.is_file():
        raise FileNotFoundError(f"DESIGN_CONFIG not found: {config}")
    sources = read_filelist(root / "rtl" / "files.f")
    if root / "rtl/sys_top.sv" not in sources:
        raise ValueError("rtl/files.f must include sys_top.sv")

    sdc = root / "constraints" / f"constraints_{args.platform}.sdc"
    if not sdc.is_file():
        raise FileNotFoundError(f"missing SDC: {sdc}")

    tech = "sky130" if args.platform == "sky130hd" else "nangate45"
    macro_root = root / "fakeram" / tech
    required = [
        macro_root / name / f"{name}.{ext}"
        for name in ("sram_sp_64x64", "sram_sp_64x256")
        for ext in ("lef", "lib", "bb.v", "v")
    ]
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise FileNotFoundError("missing SRAM collateral:\n  " + "\n  ".join(missing))

    wrapper = (root / "rtl/sram_wrap.sv").read_text()
    for cell in ("sram_sp_64x64", "sram_sp_64x256"):
        if cell not in wrapper:
            raise ValueError(f"rtl/sram_wrap.sv does not instantiate {cell}")

    print(f"design: sys_top ({args.platform})")
    print(f"RTL files: {len(sources)}")
    print(f"SDC: {sdc}")
    print(f"SRAM collateral: {macro_root}")
    print("design validation: OK")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
