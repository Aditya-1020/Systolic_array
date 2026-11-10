# Systolic Array ASIC Flow

The design uses OpenROAD-flow-scripts (ORFS) for implementation and ASICFlow for project orchestration, PVT STA, metrics and experiment tracking.

## Setup

Install ASICFlow into this project's virtual environment:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -e ../orfs-custom-flow
```

ASICFlow discovers ORFS and PDK installations from common locations. Override discovery when needed:

```bash
export ORFS_FLOW="$HOME/eda/orfs-nix/OpenROAD-flow-scripts/flow"
export PDK_ROOT="$HOME/eda/.volare"
```

## Physical design

The project manifest is `asicflow.yaml`. It records the design top, platform, RTL filelist, constraints, SRAM macro instances, timing defaults and physical settings.

```bash
orfsx -c asicflow.yaml validate
orfsx -c asicflow.yaml run synth
orfsx -c asicflow.yaml run floorplan
orfsx -c asicflow.yaml gui floorplan
orfsx -c asicflow.yaml run place
orfsx -c asicflow.yaml sta --stage place
orfsx -c asicflow.yaml sta --all
```

Use a different configuration file or set a project with `orfsx project /path/to/asicflow.yaml`. Run tags and flow variants can be overridden with `RUN_TAG` and `FLOW_VARIANT`.

The existing ORFS design Makefiles are retained for now. They continue to provide the canonical ORFS-specific settings until generated design configurations are implemented and validated. The `config/` YAML files are retained for the legacy `asicflow` CLI and are not yet removed.

## RTL verification and auxiliary flows

The existing Makefile continues to provide lint, Cocotb tests, gate-level regression, CSR generation and Fakeram generation:

```bash
make lint
make test
make regress
make csr
make fakeram
```

These workflows are intentionally independent of ORFS stage execution.

## Outputs

ORFS results remain under `build/`, with the native ORFS results/logs/reports hierarchy retained. Analysis outputs are kept with the corresponding run.

## Migration status

The manifest is the new project-facing configuration entry point for `orfsx`. The old `asicflow` CLI and legacy config tree remain available during migration; do not delete them until the replacement commands have been tested against both Sky130HD and Nangate45.
