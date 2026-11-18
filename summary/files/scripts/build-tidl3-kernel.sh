#!/usr/bin/env bash
# User-run host build/package only; no SSH, upload, installation, or reboot.
set -euo pipefail
package=$(cd -- "$(dirname -- "$0")/.." && pwd)
source_dir="$package/kernel-work/linux"
output="$package/kernel-work/out-tidl3"
release=6.18.39-arm64-k3-r47-tidl3
stage="$package/kernel-work/stage-tidl3"
[[ -f $output/.config ]] || { echo 'prepare-tidl3-kernel.sh를 먼저 실행하세요.' >&2; exit 1; }
[[ ! -e $stage ]] || { echo 'stage-tidl3가 이미 있습니다. 기존 결과를 확인하세요.' >&2; exit 1; }
for tool in make aarch64-linux-gnu-gcc aarch64-linux-gnu-strip depmod tar sha256sum; do command -v "$tool" >/dev/null; done
git -C "$source_dir" apply --reverse --check "$package/patches/0004-rpmsg-char-report-bound-local-endpoint-address.patch"
git -C "$source_dir" diff --check
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
export KBUILD_BUILD_USER=tidl KBUILD_BUILD_HOST=build-pc
args=(O="$output" LOCALVERSION=-arm64-k3-r47-tidl3)
exec > >(tee "$package/kernel-work/tidl3-build.log") 2>&1
"$source_dir/scripts/config" --file "$output/.config" --disable LOCALVERSION_AUTO
make -C "$source_dir" "${args[@]}" olddefconfig
for setting in CONFIG_DMABUF_HEAPS_CARVEOUT=y CONFIG_REMOTEPROC_TI_VISION_DMA_BUF=y CONFIG_RPMSG_CHAR=m; do
 grep -qx "$setting" "$output/.config"
done
actual=$(make -s -C "$source_dir" "${args[@]}" kernelrelease)
[[ $actual == "$release" ]] || { echo "예상하지 않은 커널 버전: $actual"; exit 1; }
make -C "$source_dir" "${args[@]}" -j"${BUILD_JOBS:-8}" Image.gz modules
mkdir -p "$stage/boot"
make -C "$source_dir" "${args[@]}" INSTALL_MOD_PATH="$stage" modules_install
install -m 0644 "$output/arch/arm64/boot/Image.gz" "$stage/boot/Image-$release.gz"
install -m 0644 "$output/.config" "$stage/boot/config-$release"
install -m 0644 "$output/System.map" "$stage/boot/System.map-$release"
# Drop host-specific build/source symlinks from the local distributable only.
rm -f "$stage/lib/modules/$release/build" "$stage/lib/modules/$release/source"
(cd "$stage" && find boot lib -type f -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
tar -czf "$package/kernel-work/$release-local-package.tar.gz" -C "$stage" .
echo '로컬 빌드·패키징 완료. 보드 업로드와 적용은 수행하지 않았습니다.'
