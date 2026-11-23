# BBAI64 TIDL Bring-Up Status and Shared-Memory Options

## Status update: Step 05 IPC initialization failure

This section supersedes the earlier DMA investigation below for the status at this point in the work.

- **Verified:** the user-applied kernel exposes the Vision Apps heap;03 host allocation/address lookup passed.49 model nodes were delegated, but remote-node creation failed on IPC. No successful DSP inference round trip yet.
- **Verified:** original04 could report success because SDK initialization overwrote the IPC error later. It now checks IPC/remote-service error logs. The earlier pass is not evidence that all IPC was healthy.
- **Verified:** TI RPMsg0.6.11 commit b1e4d172f39081db81305fa50ccaafd3ef8ae3a6 handles upstream local-endpoint src lookup failure. Its AArch64 build has the same public symbols/SONAME as SDK 0.6.10 and is prepared in a separate directory. [Files and procedure](../rpmsg-work/README-en.md)
- **Unverified:** endpoint=0 fallback with actual TIOVX round trips. The new library had not run on the board at this stage.
- **Verified:** read-only inspection found MAIN R5F0_0 running without port 13 rpmsg_chrdev. **Likely candidate cause:** waiting in ETHFW before IPC initialization. Core trace is needed for confirmation.

Next the user collects MAIN R5F0_0 trace and runs corrected04 with the per-process library override. On failure, inspect full logs and stop repeating05. Only after 04 passes should05 test remote-node creation/return. No evidence currently justifies another DT/kernel/firmware change. No remote installation or state changes were performed.

## Earlier status

**Candidate DT and Vision Apps core-start checks passed. At this earlier point, the blocker was the Linux DMA heap for Vision Apps shared-buffer allocation.**

| User result | Established scope |
|---|---|
| 01 passed | Live reserved-memory properties/core phandles match candidate checks. Without arguments, extlinux-entry naming was not checked; live DT is the relevant applied-configuration evidence |
| 02 passed | Five SDK cores (C71x, two C66x, two MAIN R5F) running; existing MCU R5F attached. Firmware matched checked SDK files. RTOS synchronization/C71x service responses are not established |
| 03 failed both as ordinary user and sudo | carveout_vision_apps_shared-memories was not a character device. Both stopped before C71x RPMsg, allocation, and address ioctl checks. Elevation did not change device exposure |

Evidence is the user-provided01–03 summaries and checks in [01](../scripts/check-live-dt.py), [02](../scripts/02-check-remoteproc.sh), [03](../scripts/03-check-ipc-dma.sh). Distinguish those summaries from unavailable full logs at the time.

## Work required up to this point

1. **Integrate the SDK memory map into BBAI64 DT.** Align per-core DMA/firmware pools, IPC, and shared regions. C71x firmware moved from stock0xa8100000 to SDK ELF0xb2100000;01 checked application. [Plan](porting-plan-en.md)
2. **Install a coherent firmware set.** Use matching C71x TIDL and participating C66x/MAIN R5F images.02 checked core start/file identity. [Mapping](../staging/manifests/firmware-map.tsv)
3. **Establish shared-buffer allocation.** DT reservation [0xb8000000,0xd8000000) alone does not register an allocator. SDK allocates from the dedicated heap, then uses /dev/remoteproc0 RPROC_IOC_DMA_BUF_ATTACH for an address. Both interfaces are needed. [Memory map](../staging/dt/sdk-memory-map.dtsi:119) · [Allocator](../../sdk_original/app_utils/utils/mem/src/app_mem_linux_dma_heap.c:85) · [Address query](../../sdk_original/app_utils/utils/mem/src/app_mem_linux_dma_heap.c:705)

## Investigation order and options

**1. Read-only follow-up.** Live DT on6.18.39-arm64-k3-r47 contains dma-heap-carveout; boot logs confirm512MiB at [0xb8000000,0xd8000000). sysfs and /dev expose only default_cma_region/reserved/system. Heap registration is the blocker; no specific exporter-registration error appeared. [Raw log](../../docs/bbai64-survey/dma-followup.log)

- **Exporter implementation Unverified:** modules, modules.builtin, configuration, and System.map names supplied no evidence. Installed files were headers without an active source link. Missing build inclusion is Likely, but exact source/patches are needed to distinguish omission from initialization failure.
- **Address ioctl Unverified:** rproc_device_ioctl is present, but matching implementation was absent from the header tree.
- **C71x RPMsg registration Verified:**64800000.dsp/remoteproc2 had virtio3.rpmsg_chrdev.-1.13/control. MAIN R5F0_0 remoteproc5 had control/name-service only. Inspect this core first if later peer setup fails.

| Option | Work and condition | Assessment |
|---|---|---|
| A. Use an exporter already in this kernel | If implemented, inspect DT binding/build/module/registration logs; then validate SDK address lookup | First choice and smallest change if existing code suffices |
| B. Backport only missing TI features | Establish omissions, then add exporter/address path to the current kernel | Retains SDK binaries/firmware; exact source/build/recovery needed. Deferred while TI Git/source access is unresolved. [TI reference](https://git.ti.com/cgit/ti-linux-kernel/ti-linux-kernel-next/tree/drivers/dma-buf/heaps/carveout-heap.c?id=0545e6ef5f73ccd870bf2c0aa41ea3567f073f35) |
| C. Modify user-space allocation | First prove contiguous memory in SDK address limits and a supported DSP address-query path; preserve cache/lifetime semantics | Avoids kernel replacement but broadens changes. Symlinking system/CMA heaps cannot meet the contract. [DMA heaps](https://docs.kernel.org/6.17/userspace-api/dma-buf-heaps.html) · [DMA-BUF](https://docs.kernel.org/driver-api/dma-buf.html) |

**2. Validate only what is needed once buffers are available.** Check actual heap allocation/address range; use errno to narrow permissions/device/UAPI if lookup fails. Then initialize SDK libraries and run one model with CPU/C71x/MMA evidence. Repeating the same03 with sudo or rerunning passed01/02 is unnecessary unless relevant DT/firmware changes occur.

Next identify exporter/ioctl branches in the exact BeagleBoard source/patch set. Current evidence does not justify DT-address/device-exposure changes. Do not finalize a minimal backport before source identity is known. If neither A nor C meets the contract, deferring this kernel/SDK-preserving route is justified.

### Follow-up established from r47 source

Public tag 6.18.39-arm64-k3-r47 at c03783811916b255c974912b3fd2eceb30fa8146 **lacks both the TI exporter and RPROC_IOC_DMA_BUF_ATTACH branch**. This supersedes the earlier Unverified status. The512MiB reservation already works, so binary reuse needs both interfaces. [Evidence](../../docs/bbai64-porting-strategy-en.md#section-14)

Both were found in a TI commit matching the SDK release string. See the [backport scope](../patches/ti-dma-backport-en.md). Returned DMA addresses must still be checked against expected shared addresses on hardware.

r47 patches passed ARM64 object builds and SDK ioctl ABI checks. Next build the full image/modules and validate heap/address behavior on a recoverable SD. [Patches/procedure](../patches/README-en.md)

The complete6.18.39-arm64-k3-r47-tidl1 image/modules and local release set were subsequently built. See the [deployment guide](r47-kernel-deployment-en.md) for post-reboot checks and offline SD recovery.
