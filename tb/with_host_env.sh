#!/usr/bin/env bash
# Run testbench simulations outside nix-shell to avoid host/Nix ABI conflicts
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENV="${ROOT}/.venv"
exec env -i \
  HOME="${HOME:-}" \
  USER="${USER:-}" \
  LANG="${LANG:-C.UTF-8}" \
  TERM="${TERM:-dumb}" \
  PATH="${VENV}/bin:/usr/local/bin:/usr/bin:/bin" \
  LD_LIBRARY_PATH="/usr/lib/x86_64-linux-gnu:/lib/x86_64-linux-gnu" \
  VIRTUAL_ENV="${VENV}" \
  PYTHONPATH="${PYTHONPATH:-}" \
  HOST_SIM_ENV=1 \
  "$@"
