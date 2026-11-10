from pathlib import Path
import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]

CONFIG_FILE = REPO_ROOT / "config" / "paths.yaml"

with open(CONFIG_FILE, "r") as f:
    CONFIG= yaml.safe_load(f)

def resolve_path(path):
    return (REPO_ROOT / path).resolve()

def get_path(category, name):
    return resolve_path(CONFIG[category][name])

RTL_DIR = get_path("directories", "rtl")
SDC_FILE = get_path("files", "design_constraints")