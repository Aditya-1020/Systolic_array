"""Compatibility entry point; use ``python -m scripts.flow`` for new workflows."""
from __future__ import annotations
import sys
from scripts.flow import main

if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
