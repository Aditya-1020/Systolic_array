from __future__ import annotations

import os
from pathlib import Path
from typing import Any

import yaml

PROJECT_ROOT = Path(__file__).resolve().parents[1]
CONFIG_FILE = PROJECT_ROOT / "paths.yaml"


def _expand(value: str, root: Path) -> Path:
    value = os.path.expanduser(os.path.expandvars(value))
    path = Path(value)
    return (path if path.is_absolute() else root / path).resolve()


def load_config() -> dict[str, Any]:
    if not CONFIG_FILE.is_file():
        raise FileNotFoundError(f"Project manifest not found: {CONFIG_FILE}")
    with CONFIG_FILE.open("r", encoding="utf-8") as stream:
        config = yaml.safe_load(stream)
    if not isinstance(config, dict):
        raise ValueError("paths.yaml must contain a YAML mapping")

    root = _expand(config.get("repository", {}).get("root", "."), PROJECT_ROOT)
    raw_paths = config.get("paths")
    design = config.get("design")
    if not isinstance(raw_paths, dict):
        raise ValueError("paths.yaml must contain a 'paths' mapping")
    if not isinstance(design, dict):
        raise ValueError("paths.yaml must contain a 'design' mapping")

    paths = {key: _expand(value, root) for key, value in raw_paths.items()}
    for key in ("name", "top", "platform", "flow_variant"):
        if not isinstance(design.get(key), str) or not design[key].strip():
            raise ValueError(f"paths.yaml design.{key} must be a non-empty string")
    return {**config, "root": root, "paths": paths}


CONFIG = load_config()
ROOT = CONFIG["root"]
PATHS = CONFIG["paths"]
DESIGN = CONFIG["design"]
