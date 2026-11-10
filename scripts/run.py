import argparse
import os
import re
import shutil
import subprocess
import sys
from paths import PATHS, ROOT

STAGES = (
    "synth",
    "floorplan",
    "place",
    "cts",
    "route",
    "finish",
    "all",
)


def validate():
    required = (
        "orfs_flow",
        "pdk_root",
        "design_config",
        "rtl_filelist",
        "sdc",
        "io_constraints",
        "fakeram_dir",
    )

    for name in required:
        path = PATHS[name]

        if not path.exists():
            raise FileNotFoundError(f"{name}: {path}")

    if not (PATHS["orfs_flow"] / "Makefile").is_file():
        raise FileNotFoundError("ORFS Makefile not found")

    if not (PATHS["pdk_root"] / "sky130A").exists():
        raise FileNotFoundError("Sky130A PDK not found under PDK_ROOT")


def run(stage, tag, dry_run=False):
    validate()

    env = os.environ.copy()

    env.update({
        "PDK_ROOT": str(PATHS["pdk_root"]),
        "PROJECT_ROOT": str(ROOT),
        "PROJECT_RTL_FILELIST": str(PATHS["rtl_filelist"]),
        "PROJECT_SDC": str(PATHS["sdc"]),
        "PROJECT_IO_CONSTRAINTS": str(PATHS["io_constraints"]),
        "PROJECT_FAKERAM_DIR": str(PATHS["fakeram_dir"]),
        "PROJECT_MACRO_PLACEMENT": str(PATHS["macro_placement"]),
    })

    work_home = PATHS["build_dir"] / "orfs" / tag

    command = [
        shutil.which("make") or "make",
        "--no-print-directory",
        "-C", str(PATHS["orfs_flow"]),
        f"DESIGN_CONFIG={PATHS['design_config']}",
        f"WORK_HOME={work_home}",
        stage,
    ]

    if dry_run:
        command.insert(1, "-n")

    print("+", " ".join(command), flush=True)

    subprocess.run(
        command,
        cwd=ROOT,
        env=env,
        check=True,
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("stage", choices=STAGES)
    parser.add_argument("--tag", default="base")
    parser.add_argument("--dry-run", action="store_true")

    args = parser.parse_args()

    if not re.fullmatch(r"[A-Za-z0-9_.-]+", args.tag):
        parser.error("Invalid run tag")

    try:
        run(args.stage, args.tag, args.dry_run)
    except (FileNotFoundError, subprocess.CalledProcessError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())