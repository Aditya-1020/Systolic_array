# interpret manifest
from pathlib import Path
import os
import yaml


PROJECT_ROOT = Path(__file__).resolve().parents[1]
CONFIG_FILE = PROJECT_ROOT / "paths.yaml"


def resolve(value):
    value = os.path.expandvars(os.path.expanduser(str(value)))
    path = Path(value)

    if not path.is_absolute():
        path = PROJECT_ROOT / path

    return path.resolve()


def load_config():
    with CONFIG_FILE.open("r", encoding="utf-8") as f:
        config = yaml.safe_load(f)

    config["root"] = resolve(config["repository"]["root"])
    config["paths"] = {
        key: resolve(value)
        for key, value in config["paths"].items()
    }

    return config


CONFIG = load_config()
ROOT = CONFIG["root"]
PATHS = CONFIG["paths"]
DESIGN = CONFIG["design"]