#!/usr/bin/env bash
# Generate and check an offline DTB candidate. No kernel build or board access.
set -euo pipefail
export LC_ALL=C

if [[ $# != 1 ]]; then
    echo "Usage: bash $0 NEW_OUTPUT_DIRECTORY" >&2
    exit 2
fi

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project=$(cd -- "$here/../.." && pwd)
dtc_dir=$project/bbai64-porting/kernel-work/out-tidl3/scripts/dtc
base=$project/bbai64-porting/staging/dt/k3-j721e-bbai64-tidl-candidate.dtb
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT

# Fixup validation needs the existing base symbols. Adding a node to an existing
# bus leaves interrupt-parent and address/size cells inherited from the base.
"$dtc_dir/dtc" -q -@ -I dts -O dtb -o "$scratch/vxe.dtbo" "$here/k3-j721e-bbai64-vxe.dtso"
"$dtc_dir/fdtoverlay" -i "$base" -o "$scratch/bbai64-tidl-vxe.dtb" "$scratch/vxe.dtbo"
"$dtc_dir/dtc" -q -s -I dtb -O dts "$base" > "$scratch/base.dts"
"$dtc_dir/dtc" -q -s -I dtb -O dts "$scratch/bbai64-tidl-vxe.dtb" > "$scratch/merged.dts"

python3 - "$scratch" <<'PY'
import re
import sys
from pathlib import Path

work = Path(sys.argv[1])
base = (work / "base.dts").read_text()
merged = (work / "merged.dts").read_text()
pattern = r"(?m)^\t\tvideo-encoder@4200000 \{\n[^{}]*^\t\t\};\n\n"
without_encoder, count = re.subn(pattern, "", merged)
if count != 1 or without_encoder != base:
    sys.exit("Unexpected DT differences beyond the single VXE node")
print("Verified: decompiled DT differs only by the VXE encoder node")
PY

mkdir -- "$1"
cp -- "$scratch/vxe.dtbo" "$scratch/bbai64-tidl-vxe.dtb" "$1/"
(cd -- "$1" && sha256sum vxe.dtbo bbai64-tidl-vxe.dtb > SHA256SUMS)
