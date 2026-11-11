# Configuration-driven ORFS flow

The generic Python runner reads three configuration layers:

- `paths.yaml`: repository root and machine-local installation/build paths.
- `config/flow.yaml`: flow defaults, generic path templates, and ORFS artifact names.
- `config/designs/<design>.yaml`: top, RTL filelist, constraints, ORFS adapter, macro instances/models.
- `config/platforms/<platform>.yaml`: technology identity, timing-library layout, and platform defines.

No SRAM model names, top module names, or platform choices are embedded in the Python runner or validator. Macro collateral is validated and passed to ORFS from the `macros` list in the design manifest.

Set `ORFS_FLOW` and `PDK_ROOT` in the environment (or in `paths.yaml`), then run:

```sh
python -m scripts.flow init
python -m scripts.flow validate
python -m scripts.flow synth --tag base --dry-run
python -m scripts.flow synth --tag base
python -m scripts.flow status
```

The flow runner expects the ORFS adapter `.mk` selected by the design manifest. The provided Sky130 and Nangate45 adapters share the same implementation.

`init` validates and creates only the configured build directory; it does not invoke synthesis. `--dry-run` does not create the run directory. `run.py` and `validate_design.py` are compatibility entry points; new work should use `scripts.flow`.
