import argparse
import os
import subprocess
from pathlib import Path

def main():
    parser = argparse.ArgumentParser(description="extract metrics from an orfs run")

    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--lib", action="append", required=True)
    parser.add_argument("--output")
    parser.add_argument("--tcl")

    args = parser.parse_args()

    run_dir = Path(args.run_dir).resolve()
    output_dir = Path(args.output).resolve() if args.output else run_dir / "metrics"

    tcl_script = (
        Path(args.tcl).resolve()
        if args.tcl
        else Path(__file__).with_suffix(".tcl").resolve()
    )

    odb_file = run_dir / "6_final.odb"
    sdc_file = run_dir / "6_final.sdc"
    spef_file = run_dir / "6_final.spef"

    lib_files = [Path(lib).resolve() for lib in args.lib]

    # check input files
    required_files = [odb_file, sdc_file, tcl_script, *lib_files]

    for file in required_files:
        if not file.is_file():
            parser.error(f"file not found: {file}")

    output_dir.mkdir(parents=True, exist_ok=True)

    # pass files to openroad
    env = os.environ.copy()
    env["ODB_FILE"] = str(odb_file)
    env["SDC_FILE"] = str(sdc_file)
    env["SPEF_FILE"] = str(spef_file) if spef_file.is_file() else ""
    env["LIB_FILES"] = " ".join(str(lib) for lib in lib_files)
    env["OUT_DIR"] = str(output_dir)

    print(f"run directory: {run_dir}")
    print(f"output directory: {output_dir}")

    subprocess.run(
        ["openroad", "-exit", str(tcl_script)],
        env=env,
        check=True
    )

    print("metrics extraction complete")


if __name__ == "__main__":
    main()
