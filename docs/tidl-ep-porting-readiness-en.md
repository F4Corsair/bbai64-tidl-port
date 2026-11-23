# BBAI64 TIDL EP Porting Readiness

## Executive Summary

**CONDITIONAL GO.** Preparation can proceed with J721E **PSDK RTOS 11.02.00.06/Linux 11.02.00.04/Tools 11_02_04_00/TI ONNX Runtime1.15.0** pinned. Debian13/Linux 6.18 hardware compatibility remains separate. [Tagged version table](https://github.com/TexasInstruments/edgeai-tidl-tools/tree/11_02_04_00#version-compatibility)

- **Verified:** ONNX EP dynamically opens libvx_tidl_rt.so, which directly depends on libtivision_apps.so.11.2.0. TIDL-RT builds OpenVX graphs; TIOVX dispatches to C71x. File inference can omit demos/log viewers, but requires the runtime/compatible firmware. Evidence: Part1 A–B.
- **Verified:** default RTOS sources synchronize multiple cores with **MCU2_0 as master**. MAIN R5F/C66x are not compute targets of the single TIDL node, yet are initialization dependencies for the supplied build. C71x-only operation needs coordinated host/RTOS IPC and synchronization changes. Part1 B.
- **Verified:** bundled BBAI64 C71x firmware region begins0xa8100000 versus Vision Apps0xb2100000. **Preferred baseline:** retain Debian/board settings and test matching DT/runtime/firmware on isolated media. Simultaneous relocation and peer reduction complicates diagnosis. Part1 C–E.

## Part1. Findings

Reused DT tables from [preanalysis](psdk-porting-preanalysis-en.md) and additionally verified EP dynamic dependencies/core synchronization. SDK-relative paths start at sdk_original/. Extracted only selected ELF/DTB members from tisdk-adas-image-j721e-evm.tar.xz temporarily for static inspection. Actual Debian boot DT/kernel source/config were not yet available.

### A. ONNX EP to C71x

```text
TI ONNX Runtime 1.15.0 / TIDLExecutionProvider
  → libtidl_onnxrt_EP: artifact loading, subgraph creation/execution
  → dlopen(libvx_tidl_rt.so), dlsym(TIDLRT_create / TIDLRT_invoke)
  → TIDL-RT: appInit → appCommonInit (memory/IPC) → tivxInit / tivxHostInit
  → OpenVX context / TIDL kernel / graph / C7x target
  → TIOVX IPC notifications + shared object descriptors and tensors
  → registered C71x target: tivxKernelTIDLCreate / Process → TIDL engine / MMA
```

| Connection | Source evidence |
|---|---|
| EP subgraph initialization/execution | c7x-mma-tidl/arm-tidl/onnxrt_ep/src/onnxrt_ep.cpp:50,312,329: dlopen/TIDL_subgraphRtCreate/TIDL_subgraphRtInvoke. common/tidl_runtimes_infer_common.cpp:333,366 and common/tidl_onnxrt_common.cpp:234 resolve/call runtime pointers |
| Indirect TIOVX dependency | rt/src/tidl_rt_ovx.c:480,656,696,1528,2429,2501,2571,2617: create/init/context/kernel loading, node/target selection, verify/process. Native tidlrt_ep/src/tidlrt_ep.cpp uses the same TIDL-RT API |
| Host initialization | rt/src/armv8/tidl_rt_linux_arm.c:123 tidl_rt_ovx_Init calls appInit. vision_apps/utils/app_init/src/app_init.c:92 initializes TIOVX after common init. platform/j721e/linux/app_init.c:175,183,226,232 configures allocation/CPU lists/descriptors/IPC. SKIP_TIOVX_INIT is for callers that already initialized; it does not remove standalone EP dependencies |
| Remote execution | tiovx/source/platform/board/common/tivx_ipc.c calls appIpcSendNotify[Port]. app_ipc_linux_rpmsg_char.c:362 maps logical C71x to TI RPMsg IDs/endpoints. tiovx_kernels/tidl/dsp/vx_tidl_target.c:1413 registers Create/Process/Delete/Control callbacks for C7x targets |

### B. Vision Apps and minimum configuration

**Verified:** bundled j7-c71_0-fw selects vision_apps_evm/vx_app_rtos_linux_c7x_1.out, containing TIDL processing strings/RPMsg resource table. rtos/c7x_1/{concerto.mak,main.c} and rtos/common/app_init.c describe its build/init: configure C7x MMU/CLEC, memory/IPC, TIOVX, then tivxRegisterTIDLTargetKernels. Echo firmware is suitable for basic IPC testing.

| Category | Minimum component/condition | Evidence |
|---|---|---|
| Required | TI ORT 1.15.0, matching libtidl_onnxrt_EP.so, J721E ONNX subgraph/network/I/O artifacts, file-input probe | A and [tag](https://github.com/TexasInstruments/edgeai-tidl-tools/tree/11_02_04_00) |
| Required | libvx_tidl_rt.so, libtivision_apps.so.11.2.0 with TIOVX/memory/IPC, libti_rpmsg_char.so.0 and dependencies | E ELF checks; preserve SONAME links |
| Required | TIDL-registering C71x firmware, matching DT, K3 remoteproc/RPMsg, host/core shared memory | app_init.c:722,896; C |
| Conditional | MAIN R5F0_0/MCU2_0, MAIN R5F0_1/MCU2_1, C66 DSP0/1 as shipped initialization peers. MCU2_0 is Linux-host RTOS synchronization master | app_cfg.h:69–81 enables peers; app_init.c:574–612 calls appLogCpuSyncInit; app_log_writer.c:329–369 waits for peer state. Linux app_ipc_linux.c:376–409 rejects failed active-peer endpoint setup |
| Unnecessary for file inference | Camera/stereo/PTK datasets/demos, DLR Python, TFLite delegate, native TIDL Python bindings, background log viewer | vision_apps_init.sh sets data/library paths and starts viewers. Required EP initialization is in-process (A). Logs remain useful diagnostically |
| Unverified | All conditional macros in supplied ELF and actual minimum peer set; removable display packages versus shipped DSO link requirements | Synchronization sources/TIDL inclusion checked; exact build manifest/maps/startup logs still needed |

For the first test, retain multicore initialization contracts and reduce Linux demo files only. A C71x-only design must revisit both CPU lists, the MCU2_0 barrier, shared-log/descriptor initialization ownership, and board services. Core startup and compute placement are separate checks.

<a id="section-06"></a>

### C. Device Tree and firmware

The table compares bundled boot/dtb/ti/k3-j721e-beagleboneai64.dtb with k3-j721e-vision-apps.dtbo. Pairs are [0] DMA/[1] firmware starts; __fixups__ identifies overlay targets. This is not the actual target Debian DT. [Upstream v6.18 DTS](https://github.com/torvalds/linux/blob/v6.18/arch/arm64/boot/dts/ti/k3-j721e-beagleboneai64.dts)

| Core | Base DTB | Vision Apps DTBO | Shipped ELF resource table |
|---|---|---|---|
| C71x | a8000000/a8100000 | b2000000/b2100000 | b2100000 |
| C66 DSP0 | a6000000/a6100000 | a9000000/a8100000 | a8100000 |
| C66 DSP1 | a7000000/a7100000 | a8000000/a9100000 | a9100000 |
| MAIN R5F0_0 | a2000000/a2100000 | Same plus two ETHFW references | a2100000 |
| MAIN R5F0_1 | a3000000/a3100000 | a4000000/a4100000 | a4100000 |
| MAIN R5F1_0/1 | a4000000/a4100000; a5000000/a5100000 | a6000000/a6100000; a7000000/a7100000 | Inspect corresponding supplied images separately |
| MCU R5F0_0/1 | a0000000/a0100000; a1000000/a1100000 | Same | Check actual boot/attachment |

- **Verified:**14 C71x PT_LOADs have a p_paddr+p_memsz DDR envelope[0xb2100000,0xb2ec0726), inside Vision Apps[0xb2100000,0xb8000000), not stock[0xa8100000,0xa9000000). RPMsg requests two vrings, dynamic DA0xffffffff,4KiB alignment,256 descriptors each. Evidence: readelf -lW -x .resource_table on vx_app_rtos_linux_c7x_1.out.
- **Verified:** beyond per-core1MiB DMA pools, shared regions include IPC[aa000000,ac000000), Vision Apps[ac000000,b2000000) with log ac000000/descriptors ac040000, heap[b8000000,d8000000), and core heaps. C71x main.c/app_mem_map.h map high scratch/heap VA0x100000000 to PA0x880000000. LOAD-only checks miss runtime regions. Evidence: rtos/{k3-j721e-rtos-memory-map.dtsi,app_mem_map.h,c7x_1/main.c}.
- **Likely:** minimum DT integration covers active-core references, disabling conflicting carveouts, shared IPC/descriptors/heaps, and peer reservations. MAIN R5F0_0 grows15→31MiB and ELF reaches0xa4000000, so moving C71x alone cannot safely enable supplied R5F images. Ethernet queues/buffers depend on MCU2_0 ETHFW/resource ownership. Review EVM board fragments against symbols/existing devices.
- **Unverified:** actual active/bootloader reservations, CMA, R5F split/lockstep/TCM, DSP DMA ranges, high-address access, and signing. Obtain actual DTBs/overlays/order/live FDT/drivers. Check64-bit ranges/phandle order/per-core LOADs in board+SoC includes and merged DT.

<a id="section-07"></a>

### D. Linux 6.18 interfaces

| Class | Findings/porting scope |
|---|---|
| Standard Linux facilities | remoteproc/virtio RPMsg, character endpoints, DMA-BUF fd sharing/sync, DMA-heap UAPI. J721E also needs K3 DSP/R5 plus TI SCI/mailbox/power/reset. Bundled6.12.57-ti modules reference devm_rproc_add/devm_ti_sci_get_by_phandle. [remoteproc](https://docs.kernel.org/staging/remoteproc.html), [DMA-BUF](https://docs.kernel.org/driver-api/dma-buf.html) |
| Possible TI-specific code | libtivision_apps contains dedicated heap,/dev/remoteproc0,/dev/mem paths. app_mem_linux_dma_heap.c implements allocation/SYNC/RPROC_IOC_DMA_BUF_ATTACH/physical mappings; dma_buf_phys.h defines ABI. A generic heap fd does not meet the address-query contract. Compare carveout exporter/binding, remoteproc_cdev/UAPI/helpers; port only established omissions or adapt host allocator/address mapping. [TI history](https://git.ti.com/cgit/ti-linux-kernel/ti-linux-kernel/commit/?id=f22103162c771ddd47372b579682445e6dc8dd0e) |
| Hardware/config checks needed | Inspect CONFIG_REMOTEPROC, K3 R5/DSP, mailbox/SCI, RPMsg virtio/char, heaps/CMA/devmem/security. Resolve remoteproc0, ioctl, heap name/address/coherence. Exact SDK 6.12.57-ti and target6.18 source-level comparison was not available; version number alone cannot prove TI functionality |

<a id="section-08"></a>

### E. AArch64 binary reuse

**Verified:** readelf -h -d -V -Ws on bundled AArch64 ELFs yielded these highest observed symbol requirements.

| Library | GLIBC/GLIBCXX | Link/loading behavior |
|---|---|---|
| usr/lib/libonnxruntime.so.1.15.0; Python 3.12 onnxruntime_pybind11_state.so | 2.38/3.4.29 | RUNPATH=$ORIGIN. Distinguish C++/Python builds; Python __init__.py also reports1.15.0 |
| libtidl_onnxrt_EP.so.1.0 | 2.38/3.4.32 | No RPATH/RUNPATH; standard direct runtime dependencies; TIDL-RT via dlopen |
| libvx_tidl_rt.so.1.0 | 2.17/3.4.32 | No RPATH/RUNPATH; directly needs libtivision_apps.so.11.2.0/libti_rpmsg_char.so.0; exports TIDLRT_create |
| libtivision_apps.so.11.2.0 | 2.38/3.4.32 | No RPATH/RUNPATH; exports appInit/appCommonInit/tivxInit/appMemInit/appIpcInit. Needs RPMsg/EGL/GLESv2/GBM even for file-based reuse |
| libti_rpmsg_char.so.0.6.10 | 2.33/not applicable | SONAME libti_rpmsg_char.so.0; libc dependency; no RPATH/RUNPATH |

**Likely:** reuse shipped DSOs through per-process paths if ABI-compatible. Start with C++ to remove Python-extension variables. For Python, compare supplied3.12 to actual Debian ABI. Check all NEEDED/SONAME/dlopen paths, TI EP registration/options, and shared-memory interfaces—not just symbol maxima. Arbitrary stock ORT/TI EP pairing does not establish provider ABI compatibility. Depending on failures, rebuild only Python bindings, TI ORT+EP, or TIDL-RT+Vision Apps/TIOVX/app_utils/RPMsg using matching headers/Debian sysroot. Host ABI failures alone do not mandate an RTOS rebuild.

## Part2. User choices

| Option | Changes | Benefits | Risks | Recommendation/timing |
|---|---|---|---|---|
| A. Shipped ELF+BBAI64 DT | Reservations/references/missing kernel features; retain peers | Reuses ELF/linker/MMU contracts | More reserved RAM, core/ETHFW/resource conflicts | First choice after baseline/review |
| B. Rebuild to stock addresses | Generator/linker/MMU/shared IPC and relevant host/RTOS builds; check shared-space capacity | Retains placement, may reduce peers | Revalidate alignment/heaps/IPC | Only if A conflicts cannot be resolved or memory constraints established |
| Debian6.18/TI comparison kernel | Port missing UAPI or prepare separate BBAI64 TI-kernel test entry | Preserve environment/obtain SDK baseline | TI kernel also needs board boot/DT validation | Debian first; decide after source/interface checks |
| Shipped DSO/source rebuild | Isolate DSOs or rebuild required modules for Debian | Smaller validation scope/control ABI/dependencies | Indirect ABI/source-tool alignment | Shipped first; scope builds from actual errors |
| Full demos/minimal user space | Full installation or EP+required DSOs/artifacts | Vendor comparison/fewer variables | Side effects/remaining firmware dependencies | Minimal user space by default; C71x-only after offload validation |

## Part3. Subsequent work

Permissions follow the user's implementation authorization.

| Stage | Work/output | Acceptance | Alternative/recovery | Authorization |
|---|---|---|---|---|
| 1. Offline baseline | Separate worktree, readelf/sha256/archive inspection; component IDs/model candidate | Reproducible origins/hashes/security variant | Resolve missing tagged J721E bundle first | Local read-only preparation needs no extra approval |
| 2. Initial SSH survey | No board writes; uname/cat/readlink/ls/logs | Actual source/config/DT/core state identified | Ask user for restricted reads or UART data | Separate SSH approval |
| 3. Recovery and DT/ELF | Test SD/old entry; isolated DTS build/merge/phandles/map | Recoverable boot/no overlap/matching core/shared addresses | Adjust DT; evaluate B if placement cannot be retained | DT/build/media-write approval |
| 4. Kernel/firmware init | Build only needed kernel features; matching DT/firmware; test remoteproc/RPMsg/heaps | Peer sync/endpoints/bidirectional patterns/coherence/repeated allocation | Isolate loader/power/IPC/heap; restore coherent baseline set | Build/kernel/firmware/reboot approval |
| 5. EP execution | Isolated loading/provider registration; pinned compilation; same input CPU/TIDL | Within defined tolerance, delegated subgraph and C71x counters/firmware evidence | Separate ABI/artifact/IPC errors; CPU-only is not offload success | Tools/build/board execution within subsequent authorization |
| 6. Reproduction | Cold boot/repeats; version/hash/I/O/log/recovery documentation | Reproduces on new environment with original boot recovery | Fix/retest first failure | Media reinstall/reboot within authorization |

### Initial read-only SSH inventory

- OS/ABI/boot: /etc/os-release, uname, package/library/Python versions, medium, kernel source/config. Supplement SPL/U-Boot/TIFS/DM versions/ABI via UART.
- DT/memory: live DT or /sys/firmware/fdt, actual DTB/DTBO/boot configuration, /proc/iomem, reserved-memory/CMA logs; extract status/firmware-name/memory-region/cluster mode/ranges/dma-ranges.
- Remoteproc/RPMsg/DMA: name/state/firmware, links/hashes, RPMsg/cdev/heaps/permissions. No core writes/ioctl/module loading in the initial survey.

## Final Recommendation

1. **CONDITIONAL GO:** begin offline preparation; modify hardware only after DT/kernel/recovery prerequisites are established.
2. Preserve Debian/BBAI64 boot chain; test **A+shipped DSOs+minimal ONNX probe** on SD, retaining supplied peers first.
3. Confirm applied DT/core ownership, signing, actual heap/ioctl support, ABI/SONAMEs, and rollback.
4. Agree SSH read-only and test-media changes for implementation. Decide firmware rebuild/kernel transition after first results.
5. Prepare hashes/SONAMEs, source/DT survey requirements, model/input/reference-output format, and offline DT/ELF gates now.

Only static analysis/report writing was performed at this stage.
