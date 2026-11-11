from __future__ import annotations

import tempfile
from pathlib import Path
from typing import Any


def _require_file(path: Path, label: str) -> None:
    if not path.is_file():
        raise FileNotFoundError(f"{label} not found: {path}")


def _require_dir(path: Path, label: str) -> None:
    if not path.is_dir():
        raise NotADirectoryError(f"{label} not found: {path}")


def read_rtl_sources(paths: dict[str, Path]) -> list[Path]:
    rtl_dir = paths["rtl_dir"]
    filelist = paths["rtl_filelist"]
    _require_dir(rtl_dir, "RTL root")
    _require_file(filelist, "RTL filelist")
    sources: list[Path] = []
    for number, raw in enumerate(filelist.read_text(encoding="utf-8").splitlines(), 1):
        entry = raw.split("#", 1)[0].strip()
        if not entry:
            continue
        candidate = Path(entry)
        source = (candidate if candidate.is_absolute() else rtl_dir / candidate).resolve()
        _require_file(source, f"{filelist}:{number} RTL source")
        if source not in sources:
            sources.append(source)
    if not sources:
        raise ValueError(f"RTL filelist contains no source files: {filelist}")
    return sources


def validate_macros(paths: dict[str, Path], design: dict[str, Any]) -> list[str]:
    macros = design.get("macros", [])
    if not isinstance(macros, list):
        raise ValueError("design manifest macros must be a list")
    models: list[str] = []
    for item in macros:
        if not isinstance(item, dict):
            raise ValueError(f"Each macro entry must be a mapping: {item!r}")
        instance, model = item.get("instance"), item.get("model")
        if not isinstance(instance, str) or not instance.strip():
            raise ValueError(f"Macro entry has invalid instance: {item!r}")
        if not isinstance(model, str) or not model.strip():
            raise ValueError(f"Macro entry has invalid model: {item!r}")
        if model not in models:
            models.append(model)
    macro_root = paths["macros_dir"]
    if models:
        _require_dir(macro_root, "Macro collateral directory")
    for model in models:
        model_dir = macro_root / model
        _require_dir(model_dir, f"Macro model directory ({model})")
        for suffix in ("lef", "lib"):
            _require_file(model_dir / f"{model}.{suffix}", f"{model} {suffix.upper()} collateral")
    return models


def validate_project(config: dict[str, Any]) -> list[Path]:
    paths = config["paths"]
    design = config["design"]
    _require_file(paths["design_config"], "ORFS design config")
    _require_file(paths["sdc"], "SDC")
    if paths.get("io_constraints") is not None:
        _require_file(paths["io_constraints"], "I/O constraints Tcl")
    _require_file(paths["orfs_flow"] / "Makefile", "ORFS Makefile")
    _require_dir(paths["orfs_flow"] / "platforms" / design["platform"], "ORFS platform")
    _require_dir(paths["pdk_root"], "PDK root")
    timing = config.get("platform", {}).get("timing", {})
    corner_dir = timing.get("corner_library_dir")
    if corner_dir:
        corner_text = str(corner_dir).replace("${PDK_ROOT}", str(paths["pdk_root"]))
        corner_text = corner_text.replace("${ORFS_FLOW}", str(paths["orfs_flow"]))
        corner_path = Path(corner_text)
        if not corner_path.is_absolute():
            corner_path = paths["orfs_flow"] / "platforms" / design["platform"] / corner_path
        _require_dir(corner_path.resolve(), "Platform timing library directory")
    sources = read_rtl_sources(paths)
    validate_macros(paths, design)
    return sources


def validate_build_writable(build: Path) -> Path:
    try:
        build.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(mode="w", prefix=".flow-write-test-", dir=build, delete=True) as probe:
            probe.write("write test\n")
            probe.flush()
    except OSError as exc:
        raise PermissionError(f"Build directory is not writable: {build}") from exc
    return build
