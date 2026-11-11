from __future__ import annotations

import importlib.util
from pathlib import Path

from scripts.config import DESIGN, PATHS


def read_rtl_sources() -> list[Path]:
    filelist = PATHS["rtl_filelist"]
    rtl_dir = PATHS["rtl_dir"]
    if not filelist.is_file():
        raise FileNotFoundError(f"RTL filelist not found: {filelist}")

    sources: list[Path] = []
    for number, raw in enumerate(filelist.read_text(encoding="utf-8").splitlines(), 1):
        entry = raw.split("#", 1)[0].strip()
        if not entry:
            continue
        item = Path(entry)
        source = (item if item.is_absolute() else rtl_dir / item).resolve()
        if not source.is_file():
            raise FileNotFoundError(f"{filelist}:{number}: missing RTL source: {source}")
        sources.append(source)

    if not sources:
        raise ValueError(f"RTL filelist is empty: {filelist}")
    top_source = (rtl_dir / f"{DESIGN['top']}.sv").resolve()
    if top_source not in sources:
        raise ValueError(f"RTL filelist does not include top source: {top_source}")
    return sources


def validate_project() -> list[Path]:
    if importlib.util.find_spec("yaml") is None:
        raise ModuleNotFoundError("PyYAML is required: python -m pip install PyYAML")

    required = (
        "orfs_flow", "pdk_root", "design_config", "rtl_dir", "rtl_filelist",
        "sdc", "io_constraints", "macros_dir",
    )
    for key in required:
        if key not in PATHS:
            raise ValueError(f"paths.yaml is missing paths.{key}")
        if not PATHS[key].exists():
            raise FileNotFoundError(f"paths.{key} does not exist: {PATHS[key]}")

    if not (PATHS["orfs_flow"] / "Makefile").is_file():
        raise FileNotFoundError(f"ORFS Makefile not found: {PATHS['orfs_flow'] / 'Makefile'}")
    pdk = PATHS["pdk_root"] / "sky130A"
    if not pdk.is_dir():
        raise FileNotFoundError(f"Sky130A PDK not found: {pdk}")
    if DESIGN["platform"] != "sky130hd":
        raise ValueError(f"Only sky130hd is currently configured, got {DESIGN['platform']}")

    sources = read_rtl_sources()
    for macro in ("sram_sp_64x64", "sram_sp_64x256"):
        for ext in ("lef", "lib"):
            path = PATHS["macros_dir"] / macro / f"{macro}.{ext}"
            if not path.is_file():
                raise FileNotFoundError(f"Missing macro collateral: {path}")

    placement = PATHS.get("macro_placement")
    if placement and not placement.is_file():
        raise FileNotFoundError(f"Macro placement Tcl not found: {placement}")
    return sources


def validate_build_writable() -> Path:
    build = PATHS["build_dir"]
    build.mkdir(parents=True, exist_ok=True)
    probe = build / ".write_test"
    try:
        probe.touch(exist_ok=False)
        probe.unlink()
    except OSError as exc:
        raise PermissionError(f"Build directory is not writable: {build}") from exc
    return build
