# Build the tidl2 Kernel on Your PC

Run on a Debian/Ubuntu x86_64 PC. Board installation is covered separately. All required files are in this bbai64-porting directory; its location is arbitrary. Commands start from the package root.

Patch0003 uses the K3 platform parent for address lookup instead of a remoteproc class device without DMA configuration. It propagates heap-mapping errors and synchronizes only mapped attachments.

## 1. Install host dependencies

The script updates apt metadata and installs the ARM64 GCC cross compiler, binutils, make, flex, bison, and kernel-build headers.

```bash
cd /actual/path/bbai64-porting
bash scripts/install-kernel-build-deps.sh
```

Internet and sudo are required. Use distribution aarch64-linux-gnu-gcc. The previous test used GCC 15; report warnings/errors from other versions. The supplied configuration is based on the final tidl1 configuration with Rust disabled; Rust tools are unnecessary.

## 2. Download source and apply patches

Run in the same terminal. Source/output go under kernel-work/. Existing directories cause a stop rather than being overwritten; select a fresh workspace or inspect previous progress first.

```bash
(
  set -euo pipefail
  package=$(pwd)
  test -f "$package/patches/r47-tidl-build.config"
  work="$package/kernel-work"
  mkdir -p "$work"
  test ! -e "$work/linux"
  git clone --depth 1 --branch 6.18.39-arm64-k3-r47 \
    https://github.com/RobertCNelson/linux-stable-rcn-ee.git "$work/linux"
  cd "$work/linux"
  test "$(git rev-parse HEAD)" = c03783811916b255c974912b3fd2eceb30fa8146
  for patch in "$package"/patches/000[123]-*.patch; do
    git apply --check "$patch"
    git apply "$patch"
  done
  git diff --check
  mkdir -p "$work/out-tidl2"
  cp "$package/patches/r47-tidl-build.config" "$work/out-tidl2/.config"
)
```

Build only after confirming the source commit and all three patches. Resolve download/application failures first. If GitHub is inaccessible, obtain an archive of the same commit, extract to a new directory, and apply patches in order.

## 3. Build image and modules

Run from the package root. Full output is saved in kernel-work/tidl2-build.log. Default parallelism is8; set BUILD_JOBS according to available RAM. A separate output directory allows retries to reuse completed objects.

```bash
(
  set -euo pipefail
  package=$(pwd)
  source_dir="$package/kernel-work/linux"
  output="$package/kernel-work/out-tidl2"
  export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
  export KBUILD_BUILD_USER=tidl KBUILD_BUILD_HOST=build-pc
  args=(O="$output" LOCALVERSION=-arm64-k3-r47-tidl2)
  cd "$source_dir"
  {
    aarch64-linux-gnu-gcc --version
    make "${args[@]}" olddefconfig
    grep -qx 'CONFIG_DMABUF_HEAPS_CARVEOUT=y' "$output/.config"
    grep -qx 'CONFIG_REMOTEPROC_TI_VISION_DMA_BUF=y' "$output/.config"
    make "${args[@]}" -j"${BUILD_JOBS:-8}" Image.gz modules
    test "$(cat "$output/include/config/kernel.release")" = 6.18.39-arm64-k3-r47-tidl2
    gzip -t "$output/arch/arm64/boot/Image.gz"
  } 2>&1 | tee "$package/kernel-work/tidl2-build.log"
)
```

make failures preserve the exit status. Inspect the first error and log tail. Success produces the compressed image/modules; continue to prepare deployment files.

## 4. Prepare local release files

```bash
(
  set -euo pipefail
  package=$(pwd)
  output="$package/kernel-work/out-tidl2"
  release=6.18.39-arm64-k3-r47-tidl2
  stage="$package/kernel-work/module-stage"
  deploy="$package/release/$release"
  test ! -e "$deploy"
  test ! -e "$stage"
  export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
  make -C "$package/kernel-work/linux" O="$output" \
    LOCALVERSION=-arm64-k3-r47-tidl2 INSTALL_MOD_PATH="$stage" \
    INSTALL_MOD_STRIP=1 modules_install
  test -s "$stage/lib/modules/$release/modules.dep"
  rm -f "$stage/lib/modules/$release/build" "$stage/lib/modules/$release/source"
  mkdir -p "$deploy"
  cp "$output/arch/arm64/boot/Image.gz" "$deploy/Image-$release.gz"
  cp "$output/.config" "$deploy/config-$release"
  tar -I 'xz -T2 -3' -cf "$deploy/modules-$release.tar.xz" \
    -C "$stage/lib/modules" "$release"
  cd "$deploy"
  sha256sum Image-*.gz modules-*.tar.xz config-* > SHA256SUMS
  sha256sum -c SHA256SUMS
)
```

This stages image, modules, configuration, and hashes locally on the PC. On failure, inspect partial release/module-stage files before retrying.

## Results and next steps

Provide the last40 lines of kernel-work/tidl2-build.log, context around the first error if any, and release/6.18.39-arm64-k3-r47-tidl2/SHA256SUMS. Follow the [board guide](../docs/r47-kernel-deployment-en.md), replacing **every tidl1 release/image/module filename with tidl2**. Retain the working tidl1 entry as the recovery target.
