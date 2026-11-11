# Systolic Array Physical Design

OpenROAD-flow-scripts (ORFS) is the physical-design engine. The Python package
in `scripts/` initializes and validates the project, organizes runs and
inspects outputs. It delegates synthesis, floorplanning, placement, CTS and
routing to native ORFS Make targets.

## Requirements

- Python 3.10+
- PyYAML in the active Python environment
- GNU Make
- ORFS checkout
- Sky130A PDK under `PDK_ROOT`
- Sky130 SRAM LEF and Liberty collateral under `fakeram/sky130`

Install PyYAML and edit the two installation paths in `paths.yaml` for your
machine. Environment variables `ORFS_FLOW` and `PDK_ROOT`, when set, override
the corresponding manifest paths. The manifest uses ordinary `${HOME}`
expansion, not shell parameter-expansion syntax.

## Initialize and validate

```sh
python -m scripts.flow init
python -m scripts.flow validate
```

Initialization validates project inputs and installation paths, creates the
build root and prints resolved configuration. It does not launch ORFS or
modify source files and is safe to repeat.

## Run ORFS

Short commands use the default tag `base`:

```sh
python -m scripts.flow synth
python -m scripts.flow floorplan
python -m scripts.flow place
python -m scripts.flow cts
python -m scripts.flow route
python -m scripts.flow all
```

Use tags to isolate experiments:

```sh
python -m scripts.flow run synth --tag baseline
python -m scripts.flow run all --tag abc_speed
python -m scripts.flow status
python -m scripts.flow status --tag baseline
python -m scripts.flow inspect --tag baseline
```

Equivalent Make targets are available: `make synth RUN_TAG=baseline`,
`make all RUN_TAG=baseline`, `make init` and `make validate`.

Runs live under `build/orfs/<tag>/`, with ORFS's native objects, logs, reports
and results directories and its platform/design/flow-variant hierarchy.

## Synthesis handoff

The mapped gate-level netlist is `1_2_yosys.v`, and the synthesis database is
`1_synth.odb`. Synthesis reports commonly include `synth_stat.txt` and
`synth_check.txt`; exact report names depend on the installed ORFS revision.
The runner does not copy outputs into a second directory.

## Configuration and hooks

- `paths.yaml`: design identity and project/install paths.
- `design-configs/sky130hd.mk`: ORFS design and synthesis variables.
- `scripts/hooks/`: project-owned Tcl/Yosys extensions.
- `scripts/flow.py`: initialization, validation, ORFS launch and inspection.

ORFS hook availability varies by revision. Verify the installed ORFS scripts
before enabling a hook. Prefer native synthesis settings and targeted hooks
over replacing the full synthesis script.

Run comparison is not implemented yet; it will be added after the baseline
synthesis and placement handoffs are reproducible.
