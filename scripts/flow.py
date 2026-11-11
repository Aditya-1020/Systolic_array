from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys

from scripts.config import CONFIG, DESIGN, PATHS, ROOT


STAGES = (
    "synth",
    "floorplan",
    "place",
    "cts",
    "route",
    "finish",
    "all",
)


def validate_project():
    required = (
        "orfs_flow",
        "pdk_root",
        "design_config",
        "rtl_filelist",
        "sdc",
        "io_constraints",
        "macros_dir",
        "macro_placement",
    )

    for name in required:
        path = PATHS[name]
        if not path.exists():
            raise FileNotFoundError(f"{name}: {path}")

    if not (PATHS["orfs_flow"] / "Makefile").is_file():
        raise FileNotFoundError("ORFS Makefile not found")

    pdk = PATHS["pdk_root"] / "sky130A"

    if not pdk.is_dir():
        raise FileNotFoundError(f"Sky130A PDK not found: {pdk}")

    sources = []

    for line in PATHS["rtl_filelist"].read_text().splitlines():
        entry = line.split("#", 1)[0].strip()

        if not entry:
            continue

        source = (PATHS["rtl_dir"] / entry).resolve()

        if not source.is_file():
            raise FileNotFoundError(f"RTL source not found: {source}")

        sources.append(source)

    if not sources:
        raise ValueError("RTL filelist is empty")

    for macro in ("sram_sp_64x64", "sram_sp_64x256"):
        for ext in ("lef", "lib"):
            path = PATHS["macros_dir"] / macro / f"{macro}.{ext}"

            if not path.is_file():
                raise FileNotFoundError(f"Missing macro collateral: {path}")

    if not (PATHS["rtl_dir"] / "sys_top.sv").is_file():
        raise FileNotFoundError("Missing sys_top.sv")

    return sources


def initialize():
    sources = validate_project()

    build = PATHS["build_dir"] / "orfs"
    build.mkdir(parents=True, exist_ok=True)

    print(f"Project       : {DESIGN['name']}")
    print(f"Top           : {DESIGN['top']}")
    print(f"Platform      : {DESIGN['platform']}")
    print(f"ORFS          : {PATHS['orfs_flow']}")
    print(f"PDK_ROOT      : {PATHS['pdk_root']}")
    print(f"DESIGN_CONFIG : {PATHS['design_config']}")
    print(f"RTL           : {len(sources)} source files")
    print(f"SDC           : {PATHS['sdc']}")
    print(f"Macros        : {PATHS['macros_dir']}")
    print(f"Build         : {build}")
    print("\nProject initialization: OK")


def run_orfs(stage, tag, dry_run=False):
    validate_project()

    if not re.fullmatch(r"[A-Za-z0-9_.-]+", tag):
        raise ValueError(f"Invalid run tag: {tag}")

    build = PATHS["build_dir"] / "orfs" / tag

    env = os.environ.copy()
    env.update({
        "PROJECT_ROOT": str(ROOT),
        "PROJECT_RTL_FILELIST": str(PATHS["rtl_filelist"]),
        "PROJECT_SDC": str(PATHS["sdc"]),
        "PROJECT_IO_CONSTRAINTS": str(PATHS["io_constraints"]),
        "PROJECT_MACROS_DIR": str(PATHS["macros_dir"]),
        "PROJECT_MACRO_PLACEMENT": str(PATHS["macro_placement"]),
        "PDK_ROOT": str(PATHS["pdk_root"]),
    })

    command = [
        "make",
        "--no-print-directory",
        "-C", str(PATHS["orfs_flow"]),
        f"DESIGN_CONFIG={PATHS['design_config']}",
        f"WORK_HOME={build}",
        f"FLOW_VARIANT={DESIGN['flow_variant']}",
        stage,
    ]

    print("+", " ".join(command), flush=True)

    if dry_run:
        command.insert(1, "-n")

    subprocess.run(
        command,
        cwd=ROOT,
        env=env,
        check=True,
    )


def main():
    parser = argparse.ArgumentParser(prog="flow")
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("init")
    subparsers.add_parser("validate")

    run_parser = subparsers.add_parser("run")
    run_parser.add_argument("stage", choices=STAGES)
    run_parser.add_argument("--tag", default="base")
    run_parser.add_argument("--dry-run", action="store_true")

    args = parser.parse_args()

    try:
        if args.command == "init":
            initialize()

        elif args.command == "validate":
            sources = validate_project()
            print(f"Project validation: OK ({len(sources)} RTL files)")

        elif args.command == "run":
            run_orfs(args.stage, args.tag, args.dry_run)

    except (FileNotFoundError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())