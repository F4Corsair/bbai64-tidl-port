# From Stock BBAI64 to TIDL Inference: Reproduction Essentials

## Verified goal and configuration

While retaining Debian, all 49/49 ResNet18 nodes were offloaded through the TI ONNX Runtime TIDL EP. One warm-up and ten inference runs produced identical repeated outputs, a maximum absolute error of 0.722227 relative to CPU inference, and a mean target.Run time of 5.715ms. These timings include debugging and host-side processing; they do not establish production performance, overall model accuracy, or direct MMA hardware-counter evidence.

| Component | Reproduction baseline |
|---|---|
| Board | BeagleBone AI-64 / J721E (TDA4VM) |
| Stock image | BeagleBoard Debian Trixie Xfce 2026-07-24, Debian 13.6 |
| Kernel | 6.18.39-arm64-k3-r47, base commit c03783811916b255c974912b3fd2eceb30fa8146 → tidl3 |
| SDK | RTOS 11.02.00.06 / corresponding Linux 11.02.00.04 |
| TIDL / MMALIB | Tools 11_02_04_00 / MMALIB 11_02_00_06 |
| Target ORT | **TI 1.15.0**; do not mix with Debian ORT 1.21 |
| Firmware | C71x, two C66x, and two MAIN R5F images from the same SDK. Rebuild MCU2_0 with ETHFW=no. Preserve the existing MCU R5F firmware |
| ORT settings | intra/inter-op=1, sequential execution, spinning off |

### Required steps only

1. Check the stock board, boot configuration, and DTB against the baseline and establish SD recovery.
2. Apply all four kernel patches and build the tidl3 image with matching modules.
3. Integrate Vision Apps reserved memory into the BBAI64 board DT. Do not replace the entire DT with an EVM tree.
4. Install a coherent firmware set, using the noeth variant for MCU2_0 from the outset.
5. Isolate TI libraries in a separate directory and select RPMsg 0.6.11 per process.
6. Use a matching model, compiled artifacts, and input generated with the pinned Tools release.
7. Validate DMA, initialization, and single/repeated inference in that order. Stop at the first failed stage.

There is no need to reproduce the intermediate tidl1/tidl2 builds, ETHFW-enabled diagnostic firmware, SIGBUS failure, or failed endpoint=0 workaround.

## Command sequence

These commands assume **the validated image and GP/unsigned-ELF configuration**. Host and board commands are separate. The user performs remote actions; do not ignore stock-file conflicts or a different baseline DTB. Without UART, recovery from lost SSH requires another PC to repair the SD card's FAT boot configuration and firmware links on the Linux root partition.

### A. Host: independent workspace and kernel

Start at the project root. Keep large generated files outside summary.

```bash
cp -a summary/files "$HOME/bbai64-repro"
cd "$HOME/bbai64-repro"
bash scripts/install-kernel-build-deps.sh
mkdir kernel-work
git clone --depth 1 --branch 6.18.39-arm64-k3-r47 \
 https://github.com/RobertCNelson/linux-stable-rcn-ee.git kernel-work/linux
test "$(git -C kernel-work/linux rev-parse HEAD)" = c03783811916b255c974912b3fd2eceb30fa8146
for p in "$PWD"/patches/000[123]-*.patch; do
 git -C kernel-work/linux apply --check "$p" && git -C kernel-work/linux apply "$p" || break
done
bash scripts/prepare-tidl3-kernel.sh
BUILD_JOBS=8 bash scripts/build-tidl3-kernel.sh
(cd kernel-work/stage-tidl3 && sha256sum -c SHA256SUMS)
```

Stop on any error. The preparation script checks the combined result of the preceding patches. Only the kernel and modules are required, not a complete OS rebuild. Use JOBS=2–4 if RAM is limited. The user performs the build; it was not run while preparing this summary.

### B. Host: extract SDK runtime files and prepare final noeth firmware

Obtain the SDK outside the repository. Replace `/actual/path` with its actual location. The exporter reads only selected libraries and unsigned firmware, checks manifest hashes, rejects mismatched versions, and avoids extracting the entire rootfs.

```bash
cd "$HOME/bbai64-repro"
python3 scripts/export-sdk-runtime.py /actual/path/SDK/tisdk-adas-image-j721e-evm.tar.xz
python3 firmware-work/prepare.py /actual/path/SDK "$HOME/bbai64-sdk-noeth"
bash firmware-work/build.sh "$HOME/bbai64-sdk-noeth" noeth build
cp "$HOME/bbai64-sdk-noeth/vision_apps/out/J721E/R5F/FREERTOS/release/vx_app_rtos_linux_mcu2_0.out" \
 staging/firmware/vision_apps_evm/vx_app_rtos_linux_mcu2_0.out
```

Use TI Arm Clang 4.0.4.LTS for firmware and preserve the original SDK. Check the noeth ELF/map load ranges and resource table against the [validation implementation](../bbai64-porting/firmware-work/check-noeth-elf.py) and [recorded result](../bbai64-porting/firmware-work/deploy-noeth/noeth-elf-validation.json). Build-location differences may change the complete-file hash; that is not a reason to skip memory validation. To use the already validated noeth ELF, copy it from the original project's deploy-noeth directory into this staging location and verify its SHA256SUMS. Skip firmware rebuilding if the same final image has already been supplied.

### C. Host: transfer only the required payload

```bash
cd "$HOME/bbai64-repro"
tar -czf "$HOME/bbai64-runtime.tar.gz" scripts src staging rpmsg-work
scp "$HOME/bbai64-runtime.tar.gz" beagle:~/
scp kernel-work/6.18.39-arm64-k3-r47-tidl3-local-package.tar.gz beagle:~/
```

Use the validated model set in the original project's `tidl/ready/resnet18/`. Large model files are not duplicated in summary.

```bash
# From the host project root
(cd tidl/ready/resnet18 && sha256sum -c SHA256SUMS)
ssh beagle 'mkdir -p ~/models/resnet18'
scp -r tidl/ready/resnet18/. beagle:models/resnet18/
```

For a fresh compilation, follow the [pinned Docker and official-model procedure](../tidl/README-en.md) and [input/quantization validation notes](../tidl/ready/resnet18/README-en.md). Do not mix model, quantization artifacts, or input sets.

### D. Board: prepare installation and check the baseline DT

```bash
mkdir -p ~/bbai64-porting
tar -xzf ~/bbai64-runtime.tar.gz -C ~/bbai64-porting
cd ~/bbai64-porting
sudo apt-get update
sudo apt-get install --yes build-essential python3 kmod
bash scripts/01-check-boot-dt.sh --baseline
```

If the baseline DTB differs, do not install the supplied candidate.dtb unchanged. Reintegrate the memory map into the actual boot DTB. If the baseline matches:

```bash
sudo install -m 0644 staging/dt/k3-j721e-bbai64-tidl-candidate.dtb /boot/firmware/ti/
```

### E. Board: kernel, firmware, and boot entry

Use [steps 2–3 of the tidl3 guide](../bbai64-porting/docs/tidl3-deployment-en.md) to verify the package and install modules and the image. **Do not use that guide's step 4 entry-generation code on a stock system: it assumes an existing tidl2 entry.** Add a manual entry as described below.

If firmware paths already exist, first identify their targets and decide how to preserve and restore them. The following commands assume those names are unused on the reproduction SD card. MCU R5F files are excluded.

```bash
cd ~/bbai64-porting
bash <<'SH'
set -euo pipefail
while read -r name image; do
 [ ! -e "/lib/firmware/$name" ] && [ ! -L "/lib/firmware/$name" ]
done < staging/manifests/firmware-map.tsv
sudo install -d /lib/firmware/bbai64-final-11.02
while read -r name image; do
 sudo install -m 0644 "staging/firmware/vision_apps_evm/$image" /lib/firmware/bbai64-final-11.02/
 sudo ln -s "bbai64-final-11.02/$image" "/lib/firmware/$name"
done < staging/manifests/firmware-map.tsv
SH
sudo cp /boot/firmware/extlinux/extlinux.conf /boot/firmware/extlinux/extlinux.conf.pre-tidl-final
sudoedit /boot/firmware/extlinux/extlinux.conf
```

Preserve the working entry and add `label tidl-final`. Set kernel to `/Image-6.18.39-arm64-k3-r47-tidl3.gz` and fdt to `/ti/k3-j721e-bbai64-tidl-candidate.dtb`. Copy append from the working entry and add `bbai64_tidl.entry=tidl-final`. Do not add fdtdir to the new entry. Set default to tidl-final. The validated setup used root=/dev/mmcblk1p3 and no initrd directive. Do not guess a different root device. If an initrd is used, first identify the actual boot file and whether it contains firmware.

Check the configuration and installed image, DT, and modules before running `sync` and `sudo reboot`. If SSH does not return, restore extlinux.conf.pre-tidl-final on the SD card. Restore the five added firmware links before booting the old DT. Preserve this minimum recovery information even when omitting a full-image backup.

### F. Board: functional checks

```bash
uname -r
cat /proc/cmdline
cd ~/bbai64-porting
bash scripts/01-check-boot-dt.sh --entry tidl-final
bash scripts/02-check-remoteproc.sh
sudo bash scripts/03-check-ipc-dma.sh --allocate
sudo env RPMSG_LIB_DIR="$PWD/rpmsg-work/diagnostic-lib" bash scripts/04-check-tidl-runtime.sh --init
sudo env RPMSG_LIB_DIR="$PWD/rpmsg-work/diagnostic-lib" \
 bash scripts/08-check-tidl-repeat.sh \
 "$HOME/models/resnet18/model.onnx" "$HOME/models/resnet18/artifacts/" \
 "$HOME/models/resnet18/input.f32" 1.0
```

A host-DMA pass with an Unverified result in 03 means DSP inference has not yet been tested. Do not proceed to inference if 04 fails. Check exit code 0, REPEAT_OK, output comparison, and a valid benchmark interval for each run in 08. Single-threaded ORT is the default; this test configuration has debug logging enabled. Do not overwrite global Debian libraries.

## Tools and remaining work

Observed host versions: ARM64 GCC 15.2.0, GNU Make 4.4.1, Python 3.14.4, Docker 29.10.0. These describe the tested environment, not necessarily mandatory exact versions. TI Arm Clang 4.0.4.LTS for firmware and Ubuntu22.04/Python 3.10/TI ORT 1.15/Tools 11_02_04_00 for model compilation are part of the release alignment. Additional host dependencies are listed in files/scripts/install-kernel-build-deps.sh. Record the installed board c++/Python 3 versions and use the supplied SDK headers.

Remaining work: reproduce this shortened procedure end to end on a clean SD card; validate reboot, long-duration, and multiple-input behavior; obtain direct MMA profiling evidence; and define application-level accuracy and performance criteria. This note captures the working configuration; the shortened sequence itself has not been rerun on a fresh stock SD card.
