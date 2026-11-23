# BBAI64 TIDL EP Board Survey and Porting Strategy

## Executive Summary

**CONDITIONAL GO.** Debian13.6/6.18.39-arm64-k3-r47 provides K3 DSP/R5F remoteproc. At this survey stage C71x/C66x/MAIN R5F are offline with firmware-load error-2. Current DT cannot load SDK Vision Apps C71x, and the dedicated heap is absent. [Board log](bbai64-survey/board.log)

Start with **strategy A**: preserve Debian/boot chain and apply matching BBAI64 DT/SDK RTOS firmware on recoverable SD. Decide kernel changes after checking exact source for exporter/TI ioctl. Static ABI favors AArch64 reuse. With Debian ORT 1.21/Python 3.13 installed, first isolate TI ORT 1.15.0/EP in a C++ path. [ABI/kernel symbols](bbai64-survey/interfaces.log)

## Part1. Findings

### OS, kernel, and boot chain

- **Verified:** BeagleBone AI-64, BeagleBoard Trixie Xfce2026-07-24, Debian13.6, AArch64 PREEMPT_RT6.18.39-arm64-k3-r47. Kernel/headers1trixie; source linux-upstream1trixie. Exact commit/vendor patches were **Unverified**. [Board log](bbai64-survey/board.log) · [More inspection](bbai64-survey/interfaces.log)
- **Verified:** root mmcblk1p3, /boot/firmware mmcblk1p1, microSD extlinux menu. U-Boot file string2026.01-g5c82fb688432. TI SCI reports11.2.8--v11.02.08/ABI4.0. **Unverified:** actual SPL/U-Boot loaded medium, separate TIFS/DM versions/security; compare UART/metadata. [Boot/SCI log](bbai64-survey/board.log)

### Effective DT and memory map

**Verified:** read all /proc/device-tree properties and resolved phandles. /sys/firmware/fdt was root-only, so use live DT. Copied boot BBAI64 DTB; default fdtoverlays is commented. Bootloader fixups/exact selection history remain **Unverified**. [Live-DT interpretation](bbai64-survey/live-dt-summary.txt) · [Boot DTB](bbai64-survey/boot-bbai64.dtb)

| Core | Board DMA→firmware start | SDK Vision Apps DMA→firmware start |
|---|---|---|
| C71x | a8000000→a8100000 | b2000000→b2100000 |
| C66 DSP0 | a7000000→a6100000 | a9000000→a8100000 |
| C66 DSP1 | a6000000→a7100000 | a8000000→a9100000 |
| MAIN R5F0_0 | a2000000→a2100000 | Same; firmware15→31MiB |
| MAIN R5F0_1 | a3000000→a3100000 | a4000000→a4100000;15→31MiB |
| MAIN R5F1_0/1 | a4000000→a4100000; a5000000→a5100000 | a6000000→a6100000; a7000000→a7100000 |
| MCU R5F0_0/1 | a0000000→a0100000; a1000000→a1100000 | Same |

- **Verified:** unlike the bundled BBAI64 DTB's contiguous C66 pairs, actual DMA pools are crossed. Index0 is DMA,1 firmware. MAIN cluster modes are0, MCU1. SDK values/ELF evidence come from prior analysis. [Live DT](bbai64-survey/live-dt-summary.txt) · [SDK comparison](tidl-ep-porting-readiness-en.md#section-06)
- **Verified:** live static reservations do not overlap. RAM banks are[0x80000000,0x100000000),[0x880000000,0x900000000). CMA[0xf3e00000,0xfce00000),144MiB, does not overlap SDK C71x[0xb2100000,0xb8000000)/heap[0xb8000000,0xd8000000). Adding C71x alone leaves other SDK regions conflicting with old DSP/R5F. Extend IPC[0xaa000000,0xabc00000) to0xac000000. [Reservations](bbai64-survey/live-dt-summary.txt) · [CMA](bbai64-survey/board.log)
- **Likely (inference):** coherent replacement of conflicting reservations/core references can integrate SDK addresses while preserving BBAI64 settings. Include IPC/descriptors/shared/C7x high heaps. EVM overlays require all external symbols/ETHFW references resolved; minimal board integration is preferred. Check restricted physical-address data and raw FDT reservations before final overlap conclusions.

### Remoteproc, firmware, and IPC

**Verified:** remoteproc0/1=C66 DSP0/1;2=C71x;5/6=MAIN R5F0_0/1;7/8=MAIN R5F1_0/1. All are offline, requesting j7-c66_{0,1}-fw, j7-c71_0-fw, j7-main-r5f{0,1}_{0,1}-fw. No matching standard/compressed files/links found; load errors are-2. MCU remoteproc3 is already attached with virtio0/char/control/ping-pong. [Devices/boot](bbai64-survey/board.log)

**Likely (inference):** probed MAIN R5F/C66 can be tested with matching DT/firmware/SCI resources; Vision Apps synchronization is not yet established. Preserve attached MCU/services. [SDK ELF/RTOS init](tidl-ep-porting-readiness-en.md)

### DMA heaps and kernel scope

| Interface | Status/next check |
|---|---|
| K3 remoteproc/SCI/virtio RPMsg/char | Verified configuration/probe/MCU endpoint. Check C71x endpoint after firmware starts |
| Standard DMA-BUF/CMA | Verified system/default_cma_region/reserved and enabled heap/CMA config; sharing/coherence Unverified |
| Vision Apps carveout | Dedicated /dev/dma_heap/carveout_vision_apps_shared-memories absent. No TI-exporter evidence in inspected config/symbols; inspect exact binding/source |
| RPROC_IOC_DMA_BUF_ATTACH | Unverified: cdev config/symbol/device do not prove dispatch. Headers lack implementation; ioctl was not called |
| Numbering/permissions | Allocator /dev/remoteproc0 identifies DSP0. Check mapped-address semantics/source and stable identification. remoteproc/RPMsg/heaps root-only; /dev/mem root:kmem0640. Runtime privileges/mapping require design |

[Configuration](bbai64-survey/kernel.config) · [Interfaces](bbai64-survey/interfaces.log) · [Allocator analysis](tidl-ep-porting-readiness-en.md#section-07)

For missing functionality compare TI6.12 exporter/binding/cdev/UAPI/DMA helpers. Minimal backports retain user space but need API/permission validation. Retaining an untouched kernel and changing allocation entails heap choice, DSP-valid addresses, lifetime/coherence—not renaming. If divergence is large, a separate TI-kernel SD can provide a firmware/runtime reference.

### TIDL runtime and ABI

**Verified:** glibc2.41/libstdc++6 14.2 include required GLIBC_2.38/GLIBCXX_3.4.32. EGL/GLESv2/GBM SONAMEs are cached. Debian ORT 1.21/Python 3.13 differ from SDK ORT 1.15.0/Python 3.12 extension. Loader cache showed no TI TIDL/Vision Apps/RPMsg DSOs. [Board ABI](bbai64-survey/interfaces.log) · [SDK SONAME analysis](tidl-ep-porting-readiness-en.md#section-08)

**Likely (inference):** isolate coherent TI ORT 1.15.0/libtidl_onnxrt_EP/libvx_tidl_rt/libtivision_apps/libti_rpmsg_char/provider libraries. Prevent mixing system libonnxruntime_providers_shared.so. Start with C++, not SDK Python bindings. Dynamic/indirect dependencies, provider registration, IPC remain **Unverified**. Baseline Linux 11.02.00.04/RTOS 11.02.00.06/Tools 11_02_04_00. [Earlier checks](tidl-ep-porting-readiness-en.md)

## Part2. Strategies and user decisions

| Priority/strategy | Feasibility/changes | Risks/selection point |
|---|---|---|
| 1. A: Debian+SDK binaries | Retain OS; coherent board DT/firmware; add TI heap/ioctl if needed; no initial RTOS rebuild | Peer/high-heap/resource/kernel/loader prerequisites. Preferred first |
| 2. B: selected A72 rebuild | Retain OS/RTOS, rebuild only DSO implicated by ABI/allocator issue with same headers; kernel preservation depends on address API | Check protocol/C++/Python ABI; select after A's exact failure |
| 3. C: RTOS/memory redesign | Retain OS; coordinate C71x/peers/IPC/linker/MMU/DT/A72 changes | Reduction/relocation broadens testing; use if A cannot resolve address/peer conflicts |
| D: separate TI-kernel comparison | Preserve Debian; prepare BBAI64 TI-kernel boot on separate SD; reuse SDK RTOS | Needs board boot support; use if backport cost/diagnostic separation warrants |

The immediate decision was whether to establish **test SD/UART recovery and proceed with A**. Decide kernel/host/RTOS modifications from source and experiments.

## Part3. Subsequent work

| Order | Work | Acceptance | Failure/recovery | Authorization |
|---|---|---|---|---|
| 1. Test environment | SD/UART, old entry/image hashes/recovery | Original reboot/restore works | Original SD; preserve eMMC | Media writes/reboot |
| 2. DT | Isolated board DTS/DTBO, merged/phandle/ELF checks | No overlap, correct PA/DA | Fix fragment conflicts; evaluate C if unresolved | DT edit/build |
| 3. Kernel | Exact-source exporter/ioctl comparison; minimal backport | Required devices/address path identified | TI reference kernel or B allocator | Local comparison allowed; build/install approved separately |
| 4. Firmware | Matching DT/ELF/signing in test entry; verify C71x/peers/MCU attachment | Load/start/synchronization pass | Restore original DT/firmware together | Installation/state changes |
| 5. IPC/DMA | Endpoints/allocation/map/address/bidirectional patterns/cache | Repeated exchange without errors | Review UAPI/core mapping first | Board tests/ioctl |
| 6. TIOVX/TIDL | Isolated DSOs/loader/appInit/IPC/targets | Correct SONAMEs/init | Select B for actual ABI failures | Install/run |
| 7. ONNX EP | Pinned compilation/TI ORT 1.15.0 C++ file input | CPU-reference tolerance | Separate artifacts/provider ABI/loader | Tools/board run |
| 8. Offloading | Delegated subgraphs and C71x firmware profiles/logs | At least one delegation, C71x/MMA evidence, repeated outputs | CPU fallback fails offload gate; inspect operators/target | Authorized board tests |
| 9. Reproduction | Images/versions/hashes/install/rollback | Cold-boot reproduction on fresh environment | Last passing set | Media writes/reboot |

Immediate local preparation: identify replacement nodes/conflicts from collected DT; trace exact kernel revision/exporter/ioctl; create firmware/DSO hash list and model acceptance criteria. Actual changes await implementation instructions.

### Conclusions

1. Retaining Debian is a realistic priority; validate the shared-memory contract first.
2. Supplied Vision Apps firmware is reusable only with matching DT/peers, not the current DT unchanged.
3. Change conflicting carveouts, active references, IPC/descriptors/heaps; preserve peripherals/boot.
4. Confirm missing TI exporter/address ioctl from exact source and add only needed features.
5. Static ABI favors SDK A72 reuse; validate isolated TI ORT 1.15.0/EP loading.
6. Start A; use B/C on corresponding failures, D for kernel comparison.
7. Recovery → DT/ELF → kernel → firmware/IPC → shared memory → runtime → ONNX/acceleration → reproduction.

### Commands and collected files

- [Main commands](bbai64-survey/commands.sh) and [output](bbai64-survey/board.log); initial model identification used tr '\000' '\n' </proc/device-tree/model.
- [Live DT archive](bbai64-survey/live-dt.tar) captures stdout from remote tar -C /proc/device-tree -chf - .; [interpretation](bbai64-survey/live-dt-summary.txt) was generated locally.
- [Boot DTB](bbai64-survey/boot-bbai64.dtb) via cat /boot/firmware/ti/k3-j721e-beagleboneai64.dtb; [config](bbai64-survey/kernel.config) via zcat /proc/config.gz or matching /boot/config-*.
- [More output](bbai64-survey/interfaces.log): dpkg-query, headers/System.map listing, symbol grep, /sbin/ldconfig -p, U-Boot strings.

Used existing SSH as an ordinary user; saved only locally. No remote writes/install/reboot/module/service/core-state/ioctl actions.

## Follow-up: Vision Apps DMA heap

Live vision_apps_shared-memories compatible=dma-heap-carveout and512MiB reservation[0xb8000000,0xd8000000) are confirmed, but dedicated heap is absent in sysfs/dev. Three standard heaps appear; C71x remoteproc2 control/char registration exists.

Modules/builtins/config/symbols give no TI exporter evidence. rproc_device_ioctl exists, but headers do not show the TI branch. Exact source/patches are needed.

Ordinary beagle SSH read DT/devices/config/modules/symbols/boot/RPMsg. [Commands](bbai64-survey/dma-followup.sh) · [Log](bbai64-survey/dma-followup.log) · [Assessment](../bbai64-porting/docs/bringup-status-en.md)

<a id="section-14"></a>

## r47 source identified

Installed linux-image-6.18.39-arm64-k3-r47 is1trixie. A matching public tag points to c03783811916b255c974912b3fd2eceb30fa8146, whose message identifies r47. Relevant defconfig agrees with hardware. This establishes release-source identity, not a reproducible binary comparison. [Origin log](bbai64-survey/kernel-origin.log) · [Commit](https://github.com/RobertCNelson/linux-stable-rcn-ee/commit/c03783811916b255c974912b3fd2eceb30fa8146)

| Feature | Source finding |
|---|---|
| Vision Apps exporter | Missing. Only system/CMA build entries; legacy CMA names alias default CMA rather than registering DT dma-heap-carveout. [Build list](https://github.com/RobertCNelson/linux-stable-rcn-ee/tree/c03783811916b255c974912b3fd2eceb30fa8146/drivers/dma-buf/heaps) |
| RPROC_IOC_DMA_BUF_ATTACH | Missing. rproc_device_ioctl supports only shutdown-on-release set/get; SDK attach reaches -EINVAL. Static source finding, no board ioctl performed. [Implementation](https://github.com/RobertCNelson/linux-stable-rcn-ee/blob/c03783811916b255c974912b3fd2eceb30fa8146/drivers/remoteproc/remoteproc_cdev.c) · [SDK request](../bbai64-porting/src/dma_buf_phys.h:33) |

SDK binary reuse needs both the exporter for512MiB and ABI-compatible lookup. Next find matching TI code/evaluate minimal r47 backport. No patch or board application was part of this survey.

## 2026-11-18 read-only follow-up to04

Collected kernel/remoteproc/RPMsg/firmware link+hash/dmesg by SSH. Record: docs/bbai64-survey/rpmsg-followup-20261118.log. [Analysis/next work](../bbai64-porting/docs/rpmsg-failure-analysis-en.md). No privileged reads or remote changes.

## Initramfs before diagnostic firmware

On2026-11-18 read uname/cmdline/boot listings/extlinux. tidl-kernel-test selects tidl2/candidate DT without initrd. Missing /boot/initrd.img matching the running release does not require generation. The old stock initramfs listing also showed no target firmware, but the primary evidence is the selected entry's lack of initrd. No remote changes.

## Collection after diagnostic firmware

Ordinary SSH collected saved trace, RPMsg/remoteproc/dmesg/links/hashes into docs/bbai64-survey/trace-firmware-result-20261118.log. Separate user authorization covered sudo reads, but sudo -n failed for password; the user supplied details. See the post-deployment section in [analysis](../bbai64-porting/docs/rpmsg-failure-analysis-en.md).

## Cache-visible trace result

Ordinary SSH collected trace-wb state/logs/hash to docs/bbai64-survey/trace-wb-result-20261118.log. Sciclient/UDMA/memory pass, then before appEthFwInit without return. [Assessment/noeth gates](../bbai64-porting/docs/rpmsg-failure-analysis-en.md). No remote changes.

## Noeth preparation/network precheck

Ordinary SSH ip -br link and driver symlinks show eth0 am65-cpsw-nuss. Record: docs/bbai64-survey/noeth-network-precheck-20261118.log. This is not a post-change network guarantee; retain SD recovery. Isolated noeth build/checks/manual guide prepared; no upload/change.

## Reassessment data and diagnostics

Ordinary SSH collected uname/GLIBC/model/input/net/io/meta/runtime hashes/C71x state to docs/bbai64-survey/reassessment-board-20261118.log; hashes match locally. Pinned Docker re-executed official preprocessing/CPU/host-TIDL on an independent artifact copy. Results: tidl/reassessment/ and [report](../bbai64-porting/docs/porting-reassessment-en.md). The next board run is manual; no upload/privileged read/inference was performed remotely.
