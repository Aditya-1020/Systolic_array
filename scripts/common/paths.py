import os
from pathlib import Path
import yaml

SCRIPT_ROOT = Path(__file__).resolve().parents[1]
CONFIG_FILE = SCRIPT_ROOT / "paths.yaml"


def expand_path(value, base):
    value = os.path.expandvars(os.path.expanduser(str(value)))
    path = Path(value)

    if not path.is_absolute():
        path = base / path

    return path.resolve()


with CONFIG_FILE.open("r", encoding="utf-8") as file:
    CONFIG = yaml.safe_load(file)

ROOT = expand_path(CONFIG["repository"]["root"], SCRIPT_ROOT)

PATHS = {
    name: expand_path(value, ROOT)
    for name, value in CONFIG["paths"].items()
}