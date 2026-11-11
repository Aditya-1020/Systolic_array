"""Open existing ORFS implementation checkpoints in the OpenROAD GUI"""
from __future__ import annotations
import os
import re
import shutil
import subprocess
from pathlib import Path
from typing import Any

GUI_STAGES = {
    "synth": "1_synth.odb",
    "floorplan": "2_floorplan.odb",
    "place": "3_place.odb",
    "cts": "4_cts.odb",
    "grt": "5_1_grt.odb",
    "route": "5_route.odb",
    "finish": "6_final.odb",
    "final": "6_final.odb",
}

ODB_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*\.odb$")


def launch_gui(stage: str, run_paths: dict[str, Path], config: dict[str, Any], env: dict[str, str]) -> None:
    """Launch OpenROAD GUI for a stage alias or exact ODB checkpoint."""

    if stage in GUI_STAGES:
        odb_name = GUI_STAGES[stage]
    else:
        odb_name = stage if stage.endswith(".odb") else f"{stage}.odb"

    if not ODB_NAME_RE.fullmatch(odb_name):
        raise ValueError(f"Invalid GUI stage or ODB filename: {stage!r}")

    results_dir = run_paths["results"].resolve()
    odb_file = (results_dir / odb_name).resolve()

    # Only allow a database directly inside this run's results directory
    if odb_file.parent != results_dir:
        raise ValueError(f"ODB must be inside the run results directory: {odb_file}")

    if not odb_file.is_file():
        available = sorted(results_dir.glob("*.odb"))
        available_names = [path.name for path in available]
        raise FileNotFoundError(f"OpenROAD database not found: {odb_file}\n" f"Available databases: {available_names or '(none)'}")

    paths = config["paths"]
    design = config["design"]

    openroad_tcl = paths["orfs_flow"] / "scripts" / "open.tcl"

    if not openroad_tcl.is_file():
        raise FileNotFoundError(f"ORFS OpenROAD GUI script not found: {openroad_tcl}")

    configured_openroad = (os.environ.get("OPENROAD_EXE") or paths.get("openroad_exe") or paths.get("openroad"))

    if configured_openroad:
        openroad = shutil.which(str(configured_openroad))
    else:
        openroad = shutil.which("openroad")

    if not openroad:
        raise FileNotFoundError("OpenROAD executable not found. " "Add it to PATH or set OPENROAD_EXE.")

    gui_env = env.copy()

    # ORFS runtime directories.
    gui_env.update({
        "WORK_HOME": str(run_paths["work_home"].resolve()),
        "OBJECTS_DIR": str(run_paths["objects"].resolve()),
        "LOG_DIR": str(run_paths["logs"].resolve()),
        "REPORTS_DIR": str(run_paths["reports"].resolve()),
        "RESULTS_DIR": str(results_dir),
    })

    # ORFS installation and design configuration.
    gui_env.update({
        "FLOW_HOME": str(paths["orfs_flow"]),
        "SCRIPTS_DIR": str(paths["orfs_flow"] / "scripts"),
        "DESIGN_CONFIG": str(paths["design_config"]),
        "PLATFORM": design["platform"],
        "DESIGN_NAME": design["top"],
        "DESIGN_NICKNAME": design["name"],
        "FLOW_VARIANT": design["flow_variant"],
        "PDK_ROOT": str(paths["pdk_root"]),
        "ODB_FILE": str(odb_file),
    })

    print(f"GUI stage : {stage}", flush=True)
    print(f"ODB       : {odb_file}", flush=True)
    print(f"OpenROAD  : {openroad}", flush=True)

    subprocess.run([openroad, "-gui", str(openroad_tcl)], cwd=config["root"], env=gui_env, check=True)
