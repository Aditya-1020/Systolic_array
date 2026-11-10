# Systolic Array ASIC Flow

The design uses OpenROAD-flow-scripts (ORFS) for synthesis and physical implementation. ASICFlow provides project-aware ORFS launch, PVT STA, metrics, experiment tracking and analysis.

## Install

Create the virtual environment in this design repository and install the sibling ASICFlow checkout into it:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -e ../orfs-custom-flow
```

The Makefile uses the active Python environment. Alternatively, run `make install` while the project environment is activated.

ASICFlow 0.4's `orfsx` runner discovers ORFS and PDK installations from common locations. For non-standard installations, set overrides:

```bash
export ORFS_FLOW="$HOME/eda/orfs-nix/OpenROAD-flow-scripts/flow"
export PDK_ROOT="$HOME/eda/.volare"
```

## Project manifest workflow

`asicflow.yaml` is the project-facing configuration for the project-first `orfsx` commands. It holds the design top, platform, RTL filelist, constraints, SRAM instances, timing defaults and selected ORFS design configuration.

```bash
orfsx --config asicflow.yaml validate
orfsx --config asicflow.yaml run synth
orfsx --config asicflow.yaml run floorplan
orfsx --config asicflow.yaml gui floorplan
orfsx --config asicflow.yaml run place
orfsx --config asicflow.yaml sta --stage place
orfsx --config asicflow.yaml sta --all
```

The Makefile exposes the same project-first path through `project-*` aliases:

```bash
make project-validate
make project-synth
make project-floorplan
make project-gui GUI_TARGET=floorplan
make project-place
make project-sta STA_STAGE=place
```

To select another project globally, run `orfsx project /path/to/asicflow.yaml`; to avoid global selection, pass `--config` on each command.

### Platform selection

The checked-in manifest defaults to Sky130HD. To use Nangate45, update these three settings together:

- `project.platform: nangate45`
- `physical.design_config: design-configs/nangate45.mk`
- `paths.macros: fakeram/nangate45`

For Sky130HD, use `design-configs/sky130hd.mk` and `fakeram/sky130`. The SDC is selected using the platform name. The six Sky130HD default PVT corners are declared in the manifest; Nangate45 uses the platform's nominal Liberty selection unless explicit corners are configured.

The existing ORFS design Makefiles remain in place because ORFS consumes `DESIGN_CONFIG` natively. They are not yet generated from the YAML. The project manifest selects the appropriate Makefile; it does not replace its ORFS-specific configuration.

## Existing advanced ASICFlow commands

The original `asicflow` command tree and `config/` YAML profiles remain available for the existing advanced workflow, including metrics, sweeps, placement helpers, reports, regression comparisons and dataset ingestion.

For example:

```bash
make synth PLATFORM=sky130hd RUN_TAG=baseline
make sta-pvt PLATFORM=sky130hd RUN_TAG=baseline STAGE=place
make metrics PLATFORM=sky130hd RUN_TAG=baseline STAGE=place
make gui PLATFORM=sky130hd GUI_TARGET=place
make sweep WHAT=util VALUES="40 50 60" SWEEP_EXECUTE=1
```

These legacy targets continue to use the existing `asicflow` configuration and run layout. Do not mix an `orfsx` run with legacy metrics/STA without deliberately pointing both tools at the same work directory; the current project-first runner and legacy context use different default work-home layouts.

## RTL verification and auxiliary flows

RTL simulation, lint, CSR generation, Fakeram generation and gate-level regression remain independent of ORFS stage execution:

```bash
make lint
make test
make regress
make csr
make fakeram
make gl-check STAGE=place
make gl-regress STAGE=place
```

## Outputs

The project-first runner writes under `build/<platform>/<run_tag>/`, retaining ORFS's native results, logs and reports hierarchy. The legacy CLI continues to use the existing `build/runs/<platform>/<design>/<run_tag>/` layout.
