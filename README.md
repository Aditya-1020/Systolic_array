# Systolic Array ASIC Flow

The project uses OpenROAD-flow-scripts (ORFS) for synthesis and physical implementation and ASICFlow for run orchestration, timing analysis, metrics collection and experiment tracking.

## Setup

Set paths for your local EDA installation:

```bash
export ORFS_FLOW="$HOME/eda/orfs-nix/OpenROAD-flow-scripts/flow"
export PDK_ROOT="$HOME/eda/.volare"
```

Clone ASICFlow beside this repository, or set `ASICFLOW_REPO` to its location:

```bash
git clone https://github.com/Aditya-1020/orfs-custom.git ../orfs-custom-flow
make install
```

## Common commands

```bash
make validate PLATFORM=sky130hd
make synth PLATFORM=sky130hd RUN_TAG=baseline
make place PLATFORM=sky130hd RUN_TAG=baseline
make sta-pvt PLATFORM=sky130hd RUN_TAG=baseline STAGE=place
make metrics PLATFORM=sky130hd RUN_TAG=baseline STAGE=place
make report PLATFORM=sky130hd
make gui PLATFORM=sky130hd GUI_TARGET=place
make gl-regress PLATFORM=sky130hd RUN_TAG=baseline STAGE=synth
make presta PLATFORM=sky130hd
```

Switch platform with `PLATFORM=nangate45`. Platform configuration selects the ORFS platform, SDC, timing libraries and corresponding Fakeram collateral. `make sta-pvt` defaults to the newest available ODB; `make metrics` defaults to placement; summary, regression and dataset commands default to final.

Each experiment is isolated by platform, design, run tag and flow variant under `build/runs/`. Metrics and run history are stored in `build/analysis/metrics.db`.

RTL simulation and lint remain independent from physical implementation. ASICFlow orchestrates ORFS; it does not replace the ORFS implementation stages.


`make gl-check` performs gate-level netlist lint. `make gl-regress` runs the APB Cocotb regression against the selected gate-level netlist. `make test` runs the RTL unit and system regressions, including the asynchronous FIFO full/empty and ordering test.
