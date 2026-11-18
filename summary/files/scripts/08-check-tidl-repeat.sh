#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
export BBAI64_REPEAT="${BBAI64_REPEAT:-10}"
export BBAI64_ORT_SINGLE_THREAD=1
exec bash "$root/scripts/06-diagnose-tidl-run.sh" "$@"
