
"""Configuration-driven ASIC physical-design flow."""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

from scripts.config import load_config
from scripts.validate import validate_build_writable, validate_project
from scripts.gui import launch_gui

STAGES = ("synth", "floorplan", "place", "cts", "route", "finish", "all")
TAG_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$")

def validate_tag(tag: str) -> str:
    if not TAG_RE.fullmatch(tag) or tag in {".", ".."}:
        raise ValueError(f"Invalid run tag: {tag!r}")
    return tag

def get_run_paths(tag: str, config: dict[str, Any] | None = None) -> dict[str, Path]:
    config = config or load_config()
    tag = validate_tag(tag)

    paths, design = config["paths"], config["design"]
    work = paths["work_home"]

    # work_home is a configured template; tag is inserted here
    work_text = str(work)

    for key, value in {
        "platform": design["platform"],
        "design": design["name"],
        "run_tag": tag,
    }.items():
        work_text = work_text.replace("{" + key + "}", value)

    if "{" in work_text or "}" in work_text:
        raise ValueError(f"Unresolved work_home template: {work_text}")

    work = Path(work_text)

    leaf = (
        Path(design["platform"])
        / design["name"]
        / design["flow_variant"]
    )

    return {
        "work_home": work,
        "objects": work / "objects" / leaf,
        "logs": work / "logs" / leaf,
        "reports": work / "reports" / leaf,
        "results": work / "results" / leaf,
    }


def _macro_models(config: dict[str, Any]) -> list[str]:
    return list(dict.fromkeys(item["model"] for item in config["design"].get("macros", [])))


def _environment(config: dict[str, Any]) -> dict[str, str]:
    p, d = config["paths"], config["design"]
    env = os.environ.copy()

    env.update({
        "PROJECT_ROOT": str(config["root"]),
        "PROJECT_RTL_DIR": str(p["rtl_dir"]),
        "PROJECT_RTL_FILELIST": str(p["rtl_filelist"]),
        "PROJECT_SDC": str(p["sdc"]),
        "PROJECT_IO_CONSTRAINTS": str(p["io_constraints"] or ""),
        "PROJECT_MACROS_DIR": str(p["macros_dir"]),
        "PROJECT_MACRO_MODELS": " ".join(_macro_models(config)),
        "PROJECT_MACRO_PLACEMENT": str(p["macro_placement"] or ""),
        "PROJECT_PLATFORM": d["platform"],
        "PROJECT_DESIGN_NAME": d["top"],
        "PROJECT_DESIGN_NICKNAME": d["name"],
        "PDK_ROOT": str(p["pdk_root"]),
        "FLOW_VARIANT": d["flow_variant"],
    })

    orfs_config = d.get("orfs", {})
    hierarchical = orfs_config.get("openroad_hierarchical", False)
    if not isinstance(hierarchical, bool):
        raise ValueError("orfs.openroad_hierarchical must be a YAML boolean")
    env["OPENROAD_HIERARCHICAL"] = str(int(hierarchical))

    return env


def initialize(config: dict[str, Any]) -> None:
    sources = validate_project(config)
    validate_build_writable(config["paths"]["build_dir"])

    p, d = config["paths"], config["design"]
    models = _macro_models(config)

    rows = (
        ("Design", d["name"]),
        ("Top", d["top"]),
        ("Platform", d["platform"]),
        ("ORFS", p["orfs_flow"]),
        ("PDK_ROOT", p["pdk_root"]),
        ("DESIGN_CONFIG", p["design_config"]),
        ("RTL sources", len(sources)),
        ("SDC", p["sdc"]),
        ("Macro models", ", ".join(models) if models else "(none)"),
        ("Macro placement", p["macro_placement"] or "(not configured)"),
        ("Build", p["build_dir"]),
    )

    for label, value in rows:
        print(f"{label:<18}: {value}")

    print("\nProject initialization: OK")


def validate(config: dict[str, Any]) -> None:
    sources = validate_project(config)
    print(f"Project validation: OK ({len(sources)} RTL source files)")


def run_stage(stage: str, tag: str = "base", dry_run: bool = False, config: dict[str, Any] | None = None) -> None:
    if stage not in STAGES:
        raise ValueError(f"Unsupported ORFS target: {stage}")

    config = config or load_config()
    validate_tag(tag)
    validate_project(config)

    p, d = config["paths"], config["design"]
    run_paths = get_run_paths(tag, config)

    if not dry_run:
        validate_build_writable(run_paths["work_home"].parent)
        run_paths["work_home"].mkdir(parents=True, exist_ok=True)

    make = shutil.which("make")

    if not make:
        raise FileNotFoundError("GNU Make was not found in PATH")

    command = [
        make,
        "--no-print-directory",
        "-C", str(p["orfs_flow"]),
        f"DESIGN_CONFIG={p['design_config']}",
        f"WORK_HOME={run_paths['work_home']}",
        f"FLOW_VARIANT={d['flow_variant']}",
        stage,
    ]

    if dry_run:
        command.insert(1, "-n")

    print("+ " + " ".join(command), flush=True)
    subprocess.run(command, cwd=config["root"], env=_environment(config), check=True)


def artifact_paths(tag: str, config: dict[str, Any] | None = None) -> dict[str, Path]:
    config = config or load_config()
    results = get_run_paths(tag, config)["results"]
    names = config["flow"].get("artifacts", {})

    return {key: results / filename for key, filename in names.items()}


def inspect_run(tag: str, config: dict[str, Any] | None = None) -> None:
    config = config or load_config()
    paths = get_run_paths(tag, config)

    print(f"Run tag : {tag}")
    print(f"Work    : {paths['work_home']}")

    found = False

    for name, path in artifact_paths(tag, config).items():
        exists = path.is_file()
        found |= exists
        print(f"{name:<18}: {'present' if exists else 'missing'}")

    if not found:
        print("No configured ORFS artifacts found.")


def status(tag: str | None = None, config: dict[str, Any] | None = None) -> None:
    config = config or load_config()

    root = (
        config["paths"]["build_dir"]
        / "runs"
        / config["design"]["platform"]
        / config["design"]["name"]
    )

    if tag:
        inspect_run(tag, config)
        return

    if not root.is_dir():
        print("No ORFS runs found.")
        return

    for path in sorted(root.iterdir()):
        if path.is_dir():
            present = [key for key, artifact in artifact_paths(path.name, config).items() if artifact.is_file()]

            print(f"{path.name:<24}: " f"{', '.join(present) if present else 'no configured outputs'}")

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

    # OpenROAD GUI
    item = sub.add_parser("gui", help="Open an existing ORFS database in OpenROAD GUI")
    item.add_argument("stage", help="Stage alias or exact ODB checkpoint stem")
    item.add_argument("--tag", default="base")

    item = sub.add_parser("status")
    item.add_argument("--tag")

    item = sub.add_parser("inspect")
    item.add_argument("--tag", required=True)

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    
    try:
        config = load_config()
        if args.command == "init":
            initialize(config)
        elif args.command == "validate":
            validate(config)
        elif args.command in STAGES:
            run_stage(args.command, args.tag, args.dry_run, config)
        elif args.command == "run":
            run_stage(args.stage, args.tag, args.dry_run, config)
        elif args.command == "gui":
            validate_tag(args.tag)
            run_paths = get_run_paths(args.tag, config)
            launch_gui(args.stage, run_paths, config,_environment(config))
        elif args.command == "status":
            status(args.tag, config)
        elif args.command == "inspect":
            inspect_run(args.tag, config)

    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
