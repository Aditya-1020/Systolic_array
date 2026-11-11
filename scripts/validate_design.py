"""Compatibility entry point for the configuration-driven validator."""
from __future__ import annotations
import sys
from scripts.config import load_config
from scripts.validate import validate_project

if __name__ == "__main__":
    try:
        cfg = load_config()
        sources = validate_project(cfg)
        print(f"Design validation: OK ({len(sources)} RTL sources)")
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
