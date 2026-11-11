from __future__ import annotations
import os
import re
from pathlib import Path
from typing import Any
import yaml

PROJECT_ROOT = Path(__file__).resolve().parents[1]
PATHS_FILE = PROJECT_ROOT / "paths.yaml"
FLOW_FILE = PROJECT_ROOT / "config" / "flow.yaml"
CONFIG_DIR = PROJECT_ROOT / "config"

def _read_yaml(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise FileNotFoundError(f"Configuration file not found: {path}")
    with path.open("r", encoding="utf-8") as stream:
        data = yaml.safe_load(stream) or {}
    if not isinstance(data, dict):
        raise ValueError(f"{path} must contain a YAML mapping")
    return data


def _expand_string(value: str, root: Path, variables: dict[str, str]) -> str:
    expanded = os.path.expanduser(os.path.expandvars(value))
    for key, replacement in variables.items():
        expanded = expanded.replace("${" + key + "}", replacement)
    return expanded


def _path(value: str, root: Path, variables: dict[str, str]) -> Path:
    expanded = _expand_string(value, root, variables)
    path = Path(expanded)
    return (path if path.is_absolute() else root / path).resolve()


def _format(value: str, values: dict[str, str]) -> str:
    try:
        return value.format_map(values)
    except KeyError as exc:
        raise ValueError(f"Unknown path template variable: {exc.args[0]} in {value!r}") from exc


def load_config() -> dict[str, Any]:
    machine = _read_yaml(PATHS_FILE)
    flow = _read_yaml(FLOW_FILE)

    repository = machine.get("repository", {})
    raw_paths = machine.get("paths", {})
    defaults = flow.get("defaults", {})
    flow_paths = flow.get("paths", {})
    if not isinstance(repository, dict) or not isinstance(raw_paths, dict):
        raise ValueError("paths.yaml must contain repository and paths mappings")
    if not isinstance(defaults, dict) or not isinstance(flow_paths, dict):
        raise ValueError("config/flow.yaml defaults and paths must be mappings")

    root_value = repository.get("root", ".")
    if not isinstance(root_value, str):
        raise ValueError("repository.root must be a string")
    root = Path(os.path.expanduser(os.path.expandvars(root_value)))
    root = (root if root.is_absolute() else PROJECT_ROOT / root).resolve()

    variables = {
        "HOME": str(Path.home()),
        "ORFS_FLOW": os.environ.get("ORFS_FLOW", str(raw_paths.get("orfs_flow", ""))),
        "PDK_ROOT": os.environ.get("PDK_ROOT", str(raw_paths.get("pdk_root", ""))),
    }
    paths: dict[str, Path] = {}
    for key, value in raw_paths.items():
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"paths.{key} must be a non-empty string")
        override = os.environ.get(key.upper())
        paths[key] = _path(override or value, root, variables)

    for key in ("orfs_flow", "pdk_root", "build_dir"):
        if key not in paths:
            raise ValueError(f"paths.yaml is missing paths.{key}")

    design_name = defaults.get("design")
    platform_name = os.environ.get("FLOW_PLATFORM", defaults.get("platform"))
    if not isinstance(design_name, str) or not design_name:
        raise ValueError("config/flow.yaml defaults.design must be a non-empty string")
    if not isinstance(platform_name, str) or not platform_name:
        raise ValueError("config/flow.yaml defaults.platform must be a non-empty string")

    design = _read_yaml(CONFIG_DIR / "designs" / f"{design_name}.yaml")
    platform = _read_yaml(CONFIG_DIR / "platforms" / f"{platform_name}.yaml")
    d = design.get("design", {})
    p = platform.get("platform", {})
    if not isinstance(d, dict) or not isinstance(p, dict):
        raise ValueError("Design and platform manifests must contain mappings named design/platform")
    if d.get("name") != design_name:
        raise ValueError(f"Design manifest name must be {design_name!r}")
    if p.get("name") != platform_name:
        raise ValueError(f"Platform manifest name must be {platform_name!r}")

    rtl = design.get("rtl", {})
    constraints = design.get("constraints", {})
    orfs = design.get("orfs", {})
    if not all(isinstance(x, dict) for x in (rtl, constraints, orfs)):
        raise ValueError("rtl, constraints and orfs sections must be mappings")

    fakeram_tech = p.get("fakeram_tech", platform_name)
    values = {
        "design": design_name,
        "platform": platform_name,
        "fakeram_tech": str(fakeram_tech),
        "design_rtl_root": str(rtl.get("root", "rtl")),
        "run_tag": "{run_tag}",
    }

    def configured_path(value: str, *, optional: bool = False) -> Path | None:
        if not value:
            return None
        return _path(_format(value, values), root, variables)

    rtl_dir = configured_path(str(rtl.get("root", "rtl")))
    filelist_value = str(rtl.get("filelist", "files.f"))
    rtl_filelist = _path(filelist_value, rtl_dir, variables)
    sdc = configured_path(str(constraints.get("default", "")))
    io_sdc = configured_path(str(constraints.get("io", "")))
    design_config = configured_path(str(orfs.get("design_config", "")))
    macro_placement_value = design.get("macro_placement")
    macro_placement = configured_path(str(macro_placement_value)) if macro_placement_value else None

    for key, value in flow_paths.items():
        if not isinstance(value, str):
            raise ValueError(f"config/flow.yaml paths.{key} must be a string")
        formatted = _format(value, values)
        if key == "rtl_dir":
            continue
        paths[key] = _path(formatted, root, variables)

    paths.update({
        "rtl_dir": rtl_dir,
        "rtl_filelist": rtl_filelist,
        "sdc": sdc,
        "io_constraints": io_sdc,
        "design_config": design_config,
        "macros_dir": _path(_format(str(flow_paths.get("fakeram_dir", "fakeram/{fakeram_tech}")), values), root, variables),
        "macro_placement": macro_placement,
        "fakeram_config": _path(_format(str(flow_paths.get("fakeram_config", "fakeram/{fakeram_tech}/{fakeram_tech}_fakeram.cfg")), values), root, variables),
    })

    design_cfg = {
        **design,
        "name": design_name,
        "top": d.get("top"),
        "platform": platform_name,
        "flow_variant": str(orfs.get("flow_variant", defaults.get("flow_variant", "base"))),
        "macros": design.get("macros", []),
    }
    return {
        "root": root,
        "paths": paths,
        "design": design_cfg,
        "platform": platform,
        "flow": flow,
        "machine": machine,
        "values": values,
    }


def main() -> None:
    config = load_config()
    print(f"Repository root: {config['root']}")
    for section in ("design", "platform"):
        print(f"{section.title()}: {config[section]}")
    print("Paths:")
    for key, value in config["paths"].items():
        print(f"  {key}: {value}")


if __name__ == "__main__":
    main()
