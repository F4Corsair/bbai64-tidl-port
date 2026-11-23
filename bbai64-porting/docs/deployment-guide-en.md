# Manual Deployment and Staged Validation

## 1. Baseline and recovery

Omit a full backup only immediately after flashing when there is no data to retain. Without UART, you must be able to repair the SD on another PC or reflash the original image if SSH does not return. If appropriate, copy extlinux.conf to another PC instead of imaging the entire card.

    sha256sum -c staging/manifests/SHA256SUMS
    bash scripts/01-check-boot-dt.sh --baseline
    findmnt -no SOURCE,TARGET /boot/firmware
    cat /proc/sys/kernel/random/boot_id

The baseline-DTB comparison checks that the candidate's source DTB matches the boot-partition file. If hashes differ, collect the current DTB and reassess the candidate.

## 2. Install the DT and add a test boot entry

The stock BBAI64 C71x firmware area starts at 0xa8100000, whereas the Vision Apps ELF uses 0xb2100000. The candidate DTB preserves collected BBAI64 board settings and integrates per-core carveouts and shared regions. A BBAI64-specific DTBO could express the same changes, but it must disable old reservations, add all regions/phandles, and be validated with U-Boot fdtoverlays support and the merged result. The TI EVM DTBO is a comparison reference because board symbols and ETHFW references differ.

    sudo install -m 0644 staging/dt/k3-j721e-bbai64-tidl-candidate.dtb /boot/firmware/ti/
    sudoedit /boot/firmware/extlinux/extlinux.conf

Clone a working entry as label tidl-test. Copy kernel, append, and any required initrd, and remove fdtdir from the test entry. Set fdt to /ti/k3-j721e-bbai64-tidl-candidate.dtb. Append bbai64_tidl.entry=tidl-test-v1 once at the **end of its existing append line**. Set the global selection to **default tidl-test**. Only the test entry receives the marker; use a new tag for a new configuration revision.

## 3. Checks that do not require kernel source

The exporter provides the heap name opened by the SDK; RPROC_IOC_DMA_BUF_ATTACH supplies the allocated buffer address. These interfaces are required for SDK inference, but not for testing candidate-DT boot or enumerating cores/RPMsg.

Proceed with the existing kernel without TI Git inspection. Before adding firmware, check the boot marker/live DT in step 5. Then install firmware in step 4 and reboot to check core states. Step 6 tests actual heap/ioctl behavior. If the heap is absent or address lookup fails, defer DMA-dependent initialization and inference. Renaming a generic CMA device does not satisfy the SDK address contract.

## 4. Install firmware

After booting the candidate DT, check requested firmware names for all five cores and GP/HS loader requirements. This step validates firmware lookup/loading and core initialization. The example below applies **only when unsigned ELF loading has been confirmed**. Select and link signed variants separately according to the actual loader contract.

```bash
sudo install -d /lib/firmware/bbai64-psdk-11.02
while read -r name image; do
  if [ -e "/lib/firmware/$name" ] || [ -L "/lib/firmware/$name" ]; then
    printf '기존 펌웨어 충돌: %s\n' "$name" >&2
    exit 1
  fi
done < staging/manifests/firmware-map.tsv
(
  set -e
  while read -r name image; do
    sudo install -m 0644 "staging/firmware/vision_apps_evm/$image" /lib/firmware/bbai64-psdk-11.02/
    sudo ln -s "bbai64-psdk-11.02/$image" "/lib/firmware/$name"
  done < staging/manifests/firmware-map.tsv
)
```

Check all five links and their target files. Leave MCU links unchanged. If deployment fails, inspect/remove only the added links on the test SD and use the original boot configuration. Apply and recover the test DT and firmware together.

## 5. Test boot and core states

After the user reboots manually, run over SSH:

    cat /proc/sys/kernel/random/boot_id
    bash scripts/01-check-boot-dt.sh --entry tidl-test-v1
    # Only after a reboot with the firmware installed
    bash scripts/02-check-remoteproc.sh

A changed boot ID identifies a new boot. The marker identifies the entry passed to the kernel; the live-DT check verifies reserved regions and phandles. If the marker is missing, check the actual boot partition and extlinux file. If the marker matches but the DT does not, check fdt. For an already booted system without a marker, run01 without arguments to inspect the live DT.

If SSH fails, mount the SD on another PC and restore the working entry as default. When reverting to the old DT after firmware installation, remove the test firmware links offline as well. If only the FAT partition can be edited, use the original SD or reflash.

## 6. IPC and DMA

Distinguish device enumeration from actual allocation, mapping, and address-query behavior.

```bash
bash scripts/03-check-ipc-dma.sh
sudo bash scripts/03-check-ipc-dma.sh --allocate
```

The first run inspects devices/endpoints. Only an authorized test operator should run the second; it needs `cc` and Linux UAPI headers. It allocates a temporary 4KiB buffer and performs mmap, cache synchronization, and the TI address ioctl. On range/ioctl failure, investigate ABI/DT/permissions and stop inference. DMA_HOST_OK with an Unverified status means only the host path passed. Later inference using C71x validates the shared-data path.

## 7. Isolated runtime

Avoid mixing Debian ORT and TI ORT, and isolate TIOVX initialization errors.

```bash
sudo install -d /opt/bbai64-porting
sudo cp -a scripts src staging /opt/bbai64-porting/
cd /opt/bbai64-porting
RESULTS_DIR="$HOME/tidl-results" bash scripts/04-check-tidl-runtime.sh
sudo env RESULTS_DIR=/var/tmp/tidl-results bash scripts/04-check-tidl-runtime.sh --init
```

Preserve global libraries and loader configuration. On loading/appInit failure, inspect SONAME/undefined-symbol errors and DMA/IPC initialization progress before continuing. A pass establishes TI runtime initialization. To withdraw the test, remove only the isolated directory on the test SD.

## 8. Prepare the model and ONNX EP

Compare CPU and EP outputs for the same input. In an x86_64 environment, use the [pinned TI example](https://github.com/TexasInstruments/edgeai-tidl-tools/tree/11_02_04_00#running-on-x86-pc). Choose a fixed-shape float32 ONNX model with one input/output from the vendor examples. The host bundle's versions.txt must match J721E and the requested release.

```bash
git clone --branch 11_02_04_00 https://github.com/TexasInstruments/edgeai-tidl-tools.git
cd edgeai-tidl-tools
./scripts/setup/setup.sh
source ./scripts/setup/setup_env.sh J721E
cd runtimes/examples/python/basic_example
python3 basic_example.py --config ./config.yaml -r onnxrt --compile
```

Use the generated model and **its complete artifact directory**. If optimization changes the model file, pin the file used to create the artifacts. Save input as a contiguous little-endian float32 array matching model shape/preprocessing with `numpy.asarray(input_tensor, dtype='<f4').tofile('input.f32')`. Establish tolerance from quantization-accuracy requirements before running. Execute on a test board with c++ available.

```bash
sudo env RESULTS_DIR=/var/tmp/tidl-results bash scripts/05-check-onnx-ep.sh \
  /path/to/model.onnx /path/to/model-artifacts /path/to/input.f32 0.05
```

0.05 is an example absolute tolerance. The user installs model, artifacts, and input on the test medium. The script builds a temporary probe against SDK ORT and compares CPU/TIDL outputs and subgraph timing. For artifact-format/provider errors, regenerate with the same tag and check library paths.

## 9. C71x/MMA evidence

Matching output may still come from CPU fallback, so check hardware-execution evidence. Require TIDL_BENCHMARK_OK and at least one processing interval, then collect C71x firmware profiling/MMA evidence from the same run. CPU fallback or missing profiles leaves final acceleration validation Unverified. On failure, preserve the same model/input/artifacts and start with the first failing stage. Record hashes, boot details, and Markdown/detailed logs in the [results template](validation-results-template-en.md).
