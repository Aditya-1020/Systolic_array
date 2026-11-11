from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

from scripts.config import DESIGN, PATHS, ROOT
from scripts.validate import validate_build_writable, validate_project

STAGES = ("synth", "floorplan", "place", "cts", "route", "finish", "all")
TAG_RE = re.compile(r"^[A-Za-z0-9_.-]+$")


def validate_tag(tag: str) -> str:
    if not TAG_RE.fullmatch(tag):
        raise ValueError(f"Invalid run tag: {tag!r}")
    return tag


def get_run_paths(tag: str) -> dict[str, Path]:
    work = PATHS["build_dir"] / "orfs" / validate_tag(tag)
    leaf = Path(DESIGN["platform"]) / DESIGN["name"] / DESIGN["flow_variant"]
    return {
        "work_home": work,
        "objects": work / "objects" / leaf,
        "logs": work / "logs" / leaf,
        "reports": work / "reports" / leaf,
        "results": work / "results" / leaf,
    }


def initialize() -> None:
    sources = validate_project()
    validate_build_writable()
    placement = PATHS.get("macro_placement")
    fields = (
        ("Project", DESIGN["name"]),
        ("Top", DESIGN["top"]),
        ("Platform", DESIGN["platform"]),
        ("ORFS", PATHS["orfs_flow"]),
        ("PDK_ROOT", PATHS["pdk_root"]),
        ("DESIGN_CONFIG", PATHS["design_config"]),
        ("RTL", f"{len(sources)} source files"),
        ("SDC", PATHS["sdc"]),
        ("Macros", "2 SRAM types"),
        ("Macro placement", placement if placement else "(ORFS default)"),
        ("Build", PATHS["build_dir"] / "orfs"),
    )
    for label, value in fields:
        print(f"{label:<17}: {value}")
    print("\nProject initialization: OK")


def validate() -> None:
    sources = validate_project()
    validate_build_writable()
    print(f"Project validation: OK ({len(sources)} RTL source files)")


def _environment() -> dict[str, str]:
    env = os.environ.copy()
    env.update({
        "PROJECT_ROOT": str(ROOT),
        "PROJECT_RTL_DIR": str(PATHS["rtl_dir"]),
        "PROJECT_RTL_FILELIST": str(PATHS["rtl_filelist"]),
        "PROJECT_SDC": str(PATHS["sdc"]),
        "PROJECT_IO_CONSTRAINTS": str(PATHS["io_constraints"]),
        "PROJECT_MACROS_DIR": str(PATHS["macros_dir"]),
        "PROJECT_MACRO_PLACEMENT": str(PATHS["macro_placement"]) if PATHS.get("macro_placement") else "",
        "PROJECT_PLATFORM": DESIGN["platform"],
        "PROJECT_DESIGN_NAME": DESIGN["top"],
        "PROJECT_DESIGN_NICKNAME": DESIGN["name"],
        "PDK_ROOT": str(PATHS["pdk_root"]),
    })
    return env


def run_stage(stage: str, tag: str = "base", dry_run: bool = False) -> None:
    if stage not in STAGES:
        raise ValueError(f"Unsupported ORFS target: {stage}")
    validate_project()
    paths = get_run_paths(tag)
    paths["work_home"].mkdir(parents=True, exist_ok=True)
    make = shutil.which("make")
    if not make:
        raise FileNotFoundError("GNU Make was not found in PATH")

    command = [
        make, "--no-print-directory", "-C", str(PATHS["orfs_flow"]),
        f"DESIGN_CONFIG={PATHS['design_config']}",
        f"WORK_HOME={paths['work_home']}",
        f"FLOW_VARIANT={DESIGN['flow_variant']}",
        stage,
    ]
    if dry_run:
        command.insert(1, "-n")
    print("+ " + " ".join(command), flush=True)
    subprocess.run(command, cwd=ROOT, env=_environment(), check=True)


def artifact_paths(tag: str) -> dict[str, Path]:
    results = get_run_paths(tag)["results"]
    return {
        "mapped_netlist": results / "1_2_yosys.v",
        "synthesis_odb": results / "1_synth.odb",
        "floorplan_odb": results / "2_floorplan.odb",
        "placement_odb": results / "3_place.odb",
        "cts_odb": results / "4_cts.odb",
        "route_odb": results / "5_route.odb",
        "final_odb": results / "6_final.odb",
        "final_gds": results / "6_final.gds",
    }


def inspect_run(tag: str) -> None:
    paths = get_run_paths(tag)
    print(f"Run tag : {tag}")
    print(f"Work    : {paths['work_home']}")
    present = False
    for name, path in artifact_paths(tag).items():
        exists = path.is_file()
        present |= exists
        print(f"{name:<17}: {'present' if exists else 'missing'}")
    if not present:
        print("No recognized ORFS stage outputs found.")


def status(tag: str | None = None) -> None:
    root = PATHS["build_dir"] / "orfs"
    if tag:
        inspect_run(tag)
        return
    if not root.is_dir():
        print("No ORFS runs found.")
        return
    tags = sorted(path.name for path in root.iterdir() if path.is_dir())
    if not tags:
        print("No ORFS runs found.")
        return
    for name in tags:
        found = [key for key, path in artifact_paths(name).items() if path.is_file()]
        print(f"{name:<24}: {', '.join(found) if found else 'no recognized outputs'}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="python -m scripts.flow")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("init")
    sub.add_parser("validate")

    for stage in STAGES:
        item = sub.add_parser(stage)
        item.add_argument("--tag", default="base")
        item.add_argument("--dry-run", action="store_true")

    item = sub.add_parser("run")
    item.add_argument("stage", choices=STAGES)
    item.add_argument("--tag", default="base")
    item.add_argument("--dry-run", action="store_true")

    item = sub.add_parser("status")
    item.add_argument("--tag")

    item = sub.add_parser("inspect")
    item.add_argument("--tag", required=True)

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.command == "init":
            initialize()
        elif args.command == "validate":
            validate()
        elif args.command in STAGES:
            run_stage(args.command, args.tag, args.dry_run)
        elif args.command == "run":
            run_stage(args.stage, args.tag, args.dry_run)
        elif args.command == "status":
            status(args.tag)
        elif args.command == "inspect":
            inspect_run(args.tag)
    except (
        FileNotFoundError, PermissionError, ValueError,
        subprocess.CalledProcessError,
    ) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
