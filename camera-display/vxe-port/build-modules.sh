#!/usr/bin/env bash
# User-run external module build using the existing tidl3 kernel output.
set -euo pipefail

if [[ $# != 1 ]]; then
    echo "Usage: bash $0 NEW_OUTPUT_DIRECTORY" >&2
    exit 2
fi

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project=$(cd -- "$here/../.." && pwd)
kernel=$project/bbai64-porting/kernel-work/out-tidl3
src=$here/ti-source
revision=0bcbb20af32ea13275b452f0e84f5a49966d0bf6
release=6.18.39-arm64-k3-r47-tidl3
cross=${CROSS_COMPILE:-aarch64-linux-gnu-}

test "$(git -C "$src" rev-parse HEAD)" = "$revision"
test "$(cat "$kernel/include/config/kernel.release")" = "$release"
test -s "$kernel/Module.symvers"
command -v modinfo >/dev/null
compiler=$("${cross}gcc" --version)
grep -Fxq "CONFIG_CC_VERSION_TEXT=\"${compiler%%$'\n'*}\"" "$kernel/.config"

mkdir -- "$1"
out=$(cd -- "$1" && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
git -C "$src" archive "$revision" | tar -xf - -C "$work"

(
    cd -- "$work"
    make ARCH=arm64 CROSS_COMPILE="$cross" KERNEL_DIR="$kernel" build
) 2>&1 | tee "$out/build.log"

vermagic=$(modinfo -F vermagic "$work/vxe-enc.ko")
test "${vermagic%% *}" = "$release"
cp -- "$work/vxe-enc.ko" "$out/"
modinfo "$out/vxe-enc.ko" > "$out/modinfo.txt"
(cd -- "$out" && sha256sum vxe-enc.ko > SHA256SUMS)
