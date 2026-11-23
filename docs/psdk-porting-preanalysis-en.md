# BBAI64 PSDK11.02 Porting Preanalysis

## 1. Executive Summary

- **Verified:** TI specifies **PSDK Linux 11.02.00.04 + RTOS 11.02.00.06** as the default J721E combination for **TIDL Tools 11_02_04_00**. The local SDK includes this RTOS release and corresponding ADAS Linux image. The requested **11.02.00.07** J721E product identity/Tools combination is **Unverified**; obtain its exact package or TI download identifier first. [TI compatibility table](https://github.com/TexasInstruments/edgeai-tidl-tools/blob/master/docs/sdk_version_compatibility_table.md#sdk-version-110200xx)
- **Verified:** bundled BBAI64 DTB and Vision Apps firmware use different DDR layouts. Stock C71x firmware starts0xa8100000; Vision Apps C71x resource table/first LOAD start0xb2100000. Replacing firmware under the stock DT fails static DDR-map checks. See DT phandle/ELF comparison in sections4–5.
- **Likely:** preserving Debian mainly requires BBAI64 DT integration and TI shared-memory kernel interfaces. AArch64 runtime reuse is possible subject to ABI checks. Validate boot-preserving remoteproc/RPMsg, shared buffers, then C71x/MMA inference. Evidence: sections3/6; gates: section 8.

## 2. Scope and SDK release verification

Unless noted, paths are relative to sdk_original/. Image paths were inspected in tisdk-adas-image-j721e-evm.tar.xz. Both archives were read, extracting only required members temporarily for static checks. No board access, installation, build, SDK/system modification occurred.

| Status | Finding | Evidence |
|---|---|---|
| Verified | Local product is TI Processor SDK RTOS for J721E EVM11.02.00.06, with A72 ADAS rootfs/boot archives | Symlink target ti-processor-sdk-rtos-j721e-evm-11_02_00_06; psdk_rtos/PROCESSOR_SDK_RTOS_release_notes.html; psdk_rtos/docs/user_guide/_sources/release_notes_11_02_00_j721e.rst.txt; sdk_builder/tools_path.mak:89 |
| Verified | Linux reference is ti-processor-sdk-linux-adas-j721e-evm-11_02_00_04 | tools_path.mak:89; [TI TVM PSDK table](https://software-dl.ti.com/codegen/docs/tvm/tvm_tidl_users_guide/getting-started/installation.html#processor-sdk-versions) |
| Verified | Tools 11_02_04_00 is the default for that J721E combination | [Compatibility table](https://github.com/TexasInstruments/edgeai-tidl-tools/blob/master/docs/sdk_version_compatibility_table.md#sdk-version-110200xx), [release](https://github.com/TexasInstruments/edgeai-tidl-tools/releases/tag/11_02_04_00) |
| Unverified | Exact .07 product/J721E distribution/Tools pairing. Source tags contain11.02.00.07; Analytics .07 manifest changes identify J722S, and DM firmware has separate tags | [Manifest history](https://git.ti.com/cgit/processor-sdk/psdk_repo_manifests/log/), [PDK Sciclient history](https://git.ti.com/cgit/processor-sdk/pdk/log/packages/ti/drv/sciclient/soc). Need a J721E .07 download page, manifest, compatibility notes |
| Unverified | Standalone host Tools 11_02_04_00 installed locally; c7x-mma-tidl/tidl_tools contains broken links including tidl_model_import.so | Obtain matching J721E host-bundle versions.txt, real files, checksums |

## 3. PSDK components and dependencies

| Component | Baseline/files | Porting assessment |
|---|---|---|
| Linux | Bundled usr/lib/modules/6.12.57-ti-01343-g15b58b1dcd0e-dirty; Arago2025.01 in usr/lib/os-release | Bundled baseline Verified; TI validation on Debian13/6.18 Unverified |
| Bootloader | boot-adas-j721e-evm.tar.gz: tiboot3-…-2025.01+git97423+df1fe23-…bin, tispl.bin, u-boot.img, uEnv.txt; archive version20260123_adas | EVM U-Boot2025.01 packaging Verified. Likely retain BBAI64 chain; require boot/TI SCI/core-control success |
| System firmware | sysfw.itb and GP/HS variants; PDK packages/ti/drv/sciclient supplies TI SCI/board configuration | Exact embedded TIFS/DM versions and board ABI Unverified. Check FIT/metadata, boot-console versions/ABI, resources |
| Setup/build entry points | sdk_builder/scripts/setup_psdk_rtos.sh, tools_path.mak; vision_apps/apps/basic_demos/app_linux_fs_files/vision_apps_init.sh and vision_apps_evm/run_app_tidl.sh | Verified references; review hardcoded paths, services/firmware links, kernel devices before porting |
| TIOVX/Vision Apps | tiovx/include/TI/; vision_apps/platform/j721e/linux/app_init.c; rtos/app_mem_map.h; app_utils/utils/mem/src/app_mem_linux_dma_heap.c | Verified separation of A72 initialization, RTOS map, Linux allocation. Align host/remote IPC and memory contracts |
| TIDL/MMA/IPC | c7x-mma-tidl/arm-tidl/; mmalib_11_02_00_06/; pdk_jacinto_11_02_00_15/packages/ti/drv/ipc/; image usr/lib/firmware/{ti-ipc/j721e,vision_apps_evm}/ | Verified Linux EP, C7x/MMA, RTOS IPC, and two firmware families |

## 4. BBAI64 versus PSDK DTS

**Verified:** the actual target Debian DTS/DTB was unavailable. BBAI64 below means bundled boot/dtb/ti/k3-j721e-beagleboneai64.dtb. EVM references are k3-j721e-common-proc-board.dtb and k3-j721e-vision-apps.dtbo in the same image. Targets were resolved from phandles, __fixups__, and __local_fixups__. [Upstream v6.18 BBAI64 DTS](https://github.com/torvalds/linux/blob/v6.18/arch/arm64/boot/dts/ti/k3-j721e-beagleboneai64.dts) is a reference once actual kernel source is known.

Each pair is memory-region[0] DMA start → [1] firmware start. All DMA regions are1MiB; firmware ends are exclusive.

| Node / firmware-name | Stock BBAI64 pair/end | EVM Vision Apps pair/end |
|---|---|---|
| MCU R5F0_0 / j7-mcu-r5f0_0-fw | a0000000 → a0100000 / a1000000 | Same |
| MCU R5F0_1 / j7-mcu-r5f0_1-fw | a1000000 → a1100000 / a2000000 | Same |
| MAIN R5F0_0 / j7-main-r5f0_0-fw | a2000000 → a2100000 / a3000000 | a2000000 → a2100000 / a4000000 |
| MAIN R5F0_1 / j7-main-r5f0_1-fw | a3000000 → a3100000 / a4000000 | a4000000 → a4100000 / a6000000 |
| MAIN R5F1_0 / j7-main-r5f1_0-fw | a4000000 → a4100000 / a5000000 | a6000000 → a6100000 / a7000000 |
| MAIN R5F1_1 / j7-main-r5f1_1-fw | a5000000 → a5100000 / a6000000 | a7000000 → a7100000 / a8000000 |
| DSP0 dsp@4d80800000 / j7-c66_0-fw | a6000000 → a6100000 / a7000000 | a9000000 → a8100000 / a9000000 |
| DSP1 dsp@4d81800000 / j7-c66_1-fw | a7000000 → a7100000 / a8000000 | a8000000 → a9100000 / aa000000 |
| C71x dsp@64800000 / j7-c71_0-fw | a8000000 → a8100000 / a9000000 | b2000000 → b2100000 / b8000000 |

- **Verified:** DSP compatible strings are ti,j721e-c66-dsp/ti,j721e-c71-dsp with status="okay". R5 cores use ti,j721e-r5f without explicit core status in the compared base DTB; check parent status/ti,cluster-mode on hardware. Vision Apps adds virtual-Ethernet queues/buffers at MAIN R5F0_0 indices2/3.
- **Verified:** base EVM crosses C66 DMA: DSP0 a7000000→a6100000, DSP1 a6000000→a7100000. Bundled BBAI64 uses contiguous pairs above. Both Vision Apps/Edge AI overlays reassign using crossed EVM-style associations and disable original reservations. Check external symbols/merged DT before deciding on BBAI64 application.
- **Verified:** within each profile, static shared-dma-pool/no-map DMA/firmware regions do not overlap and starts/sizes are MiB-aligned. Neither overlaps stock OP-TEE[0x9e800000,0xa0000000). Enabling both profiles causes collisions; Vision Apps MAIN R5F1_0, for example, occupies the stock BBAI64 DSP0 pair.

| Additional region | Stock BBAI64 | Vision Apps range, exclusive end |
|---|---|---|
| RTOS IPC | 0xaa000000–0xabc00000,28MiB | 0xaa000000–0xac000000,32MiB; alignment0x1000,no-map |
| Vision Apps DMA memory | Absent | 0xac000000–0xb2000000,96MiB; shared-dma-pool,no-map |
| Linux shared heap | Absent | 0xb8000000–0xd8000000,512MiB; dma-heap-carveout |
| Core heaps/ETHFW | Absent | Low0xd8000000–0xe4000000; ETH queues0xe4000000–0xe4800000; buffers0xe4800000–0xe6000000; high0x880000000–0x8a7000000. All shared-dma-pool/no-map |

**Verified:** numerical comparison against BBAI64 RAM banks[0x80000000,0x100000000) and[0x880000000,0x900000000) places all ranges inside RAM and shows no overlap among Vision Apps regions. Base EVM separately has dynamic linux,cma (shared-dma-pool/reusable). **Unverified:** actual target CMA, bootloader reservations, DMA masks/translation, high-heap access. Obtain /memory, /reserved-memory, parent ranges/dma-ranges, CMA size/alignment/alloc-ranges, and boot logs. Evidence: both base DTBs and vision_apps/platform/j721e/rtos/k3-j721e-rtos-memory-map.dtsi.

## 5. Remoteproc, firmware, and memory-map compatibility

**Verified:** image usr/lib/firmware/j7-*-fw links select these Vision Apps ELFs. Compared PT_LOAD physical addresses/memory sizes and .resource_table using readelf -lW/-SW. DDR envelopes include gaps.

| Image under usr/lib/firmware/vision_apps_evm/ | DDR envelope/resource table | Static assessment |
|---|---|---|
| vx_app_rtos_linux_c6x_1.out | a8100000–a85ea278 / a8100000 | Fits Vision Apps DSP0, not stock BBAI64 DSP0 |
| vx_app_rtos_linux_c6x_2.out | a9100000–a95ea278 / a9100000 | Fits Vision Apps DSP1, not stock DSP1 |
| vx_app_rtos_linux_c7x_1.out | b2100000–b2ec0726 / b2100000 | Fits Vision Apps C71x, not stock C71x |
| vx_app_rtos_linux_mcu2_0.out | a2100000–a4000000 / a2100000 | Needs31MiB Vision Apps MAIN R5F0_0; exceeds stock end |
| vx_app_rtos_linux_mcu2_1.out | a4100000–a6000000 / a4100000 | Fits Vision Apps MAIN R5F0_1, not stock |

Both R5F images also load at DA0x0; validate via driver TCM translation/cluster mode. -fw-sec links select signed images. The table covers unsigned ELFs; target security/loader variant is **Unverified**. Evidence: ELFs/links and vision_apps/platform/j721e/rtos/{c66x_1,c66x_2,c7x_1,mcu2_0,mcu2_1}/linker_mem_map.cmd.

- **Verified:** supplied overlays explicitly implement the crossed C66 layout, and each ELF matches its core's second phandle. TI DSP remoteproc initializes index0 as vring DMA pool and maps subsequent static carveouts. C71x RPMsg requests two host-allocated DA0xffffffff vrings aligned0x1000,256 descriptors each. Validate firmware placement separately from DMA-pool association. **Unverified:** the design rationale for crossed addresses and actual Debian-driver interpretation need the effective DT/driver. [TI DSP driver](https://git.ti.com/cgit/ti-linux-kernel/ti-linux-kernel-next/tree/drivers/remoteproc/ti_k3_dsp_remoteproc.c?id=d37a4165531158223df79c9d5b12bed96699cc89)
- **Verified:** IPC-echo DSP0/DSP1/C71x images under usr/lib/firmware/ti-ipc/j721e/ have resource tables at a6100000/a7100000/a8100000 and fit stock BBAI64. They are candidates for isolated IPC testing; Vision Apps loading/runtime is a separate stage.
- **Unverified:** R5F TCM/DSP local RAM/high-heap DA↔PA translation/permissions. Compare K3 da_to_va/reserved-memory code, linker/MMU settings, and TI SCI ownership.

## 6. TIOVX/TIDL runtime porting requirements

| Status | Requirement/gate | Evidence |
|---|---|---|
| Likely | A72 ONNX/native TIDL EPs are binary-reuse candidates. Both are AArch64 and directly need libstdc++.so.6/libgcc_s.so.1/libm.so.6/libc.so.6. Check GLIBC_2.38/GLIBCXX_3.4.32, all indirect/lazy dependencies, and actual runtime loading | c7x-mma-tidl/arm-tidl/{onnxrt_ep,tidlrt_ep}/out/J721E/A72/LINUX/release/*.so.1.0, readelf -hdV |
| Likely | Retain Debian K3 remoteproc/mailbox/TI SCI power/reset/virtio RPMsg if functional. Compare memory-region order, mboxes, power-domains, resets, SCI handles, R5 cluster mode with actual bindings; require echo round trip | DTs in section 4, TI drivers, pdk_jacinto_11_02_00_15/packages/ti/drv/ipc/ |
| Verified | Allocator opens carveout_vision_apps_shared-memories or build-dependent carveout_edgeai_shared-memories. Uses DMA_HEAP_IOCTL_ALLOC/DMA_BUF_IOCTL_SYNC/RPROC_IOC_DMA_BUF_ATTACH and /dev/remoteproc0 | app_mem_linux_dma_heap.c DMA_HEAP_NAME/ioctls/device path |
| Likely | Missing exporter/ioctl in6.18 requires TI driver backport or supported allocator-source port. More CMA alone cannot meet heap-name/ioctl/DSP-address contracts; validate fd allocation/sharing/address/bidirectional patterns | Allocator, dma-heap-carveout DT, [TI heap history](https://git.ti.com/cgit/ti-linux-kernel/ti-linux-kernel/commit/?id=f22103162c771ddd47372b579682445e6dc8dd0e) |
| Likely | Reuse Vision Apps firmware only while retaining map/IPC contracts. Relocation requires coherent DTS/linker/app_mem_map.h/MMU/MPU/shared-IPC changes | gen_linker_mem_map.py, app_mem_map.h, linker_mem_map.cmd, section 5 |
| Verified | Compile for J721E with aligned host Tools/runtime and deploy matching libraries/firmware | [Pinned README](https://github.com/TexasInstruments/edgeai-tidl-tools/tree/11_02_04_00), [artifact incompatibility diagnostics](https://github.com/TexasInstruments/edgeai-tidl-tools/blob/master/docs/debugging.md#model-artifacts-incompatibility) |

## 7. Anticipated issues and risks

| Priority | Assessment/caution |
|---|---|
| High | Verified: mixed DT/firmware layouts cause DDR collisions. Check disabled old/active new reservations in merged DT; validate/restore DT and firmware together. Sections4–5 |
| High | Likely: EVM overlays reference missing board symbols/resources. Boot uEnv.txt loads k3-j721e-evm-ethfw.dtbo plus Vision Apps. Port needed fragments and recheck Ethernet/eMMC/SD/console |
| High | Unverified: existing SCI ownership and GP/HS choice may not satisfy firmware. Use boot-console/remoteproc/first errors to distinguish authentication/power/reset. Sections3/5 |
| High | Likely: an open heap can still fail address lookup/cache/DSP access. Resolve remoteproc0 mapping; test bidirectional data/repeated allocations before inference. Section6 |
| Medium | Likely: distinguish ABI/artifact-version errors from CPU fallback. Check EP registration/delegated subgraphs/C7x profiles, not output/latency alone. Sections6/8 |

## 8. Recommended sequence and gates

These are subsequent porting steps. Use a test SD and separate sources; preserve each result/boot log.

| Step | Work/caution | Pass or stop criteria |
|---|---|---|
| 1. Pin versions | If J721E .07 evidence appears, verify its manifest first. Otherwise record official Linux.04/RTOS.06/Tools 11_02_04_00 and all kernel/DT/firmware/library/tool tags/hashes | Every experimental component has an identified origin/version pairing |
| 2. Recoverable baseline | Use UART/test SD to verify Debian boot and restoring the original entry; preserve eMMC/bootloader; collect base/effective DT/links/logs | Repeatable stock storage/network/boot and recoverable selection |
| 3. Baseline remoteproc/IPC | Use firmware matching stock DT; for echo first check section 5 addresses/security; inspect prestarted cores/cluster mode | Correct core/firmware and service round trip. Otherwise narrow mailbox/power/reset/SCI/load addresses |
| 4. Board DT/kernel | Integrate Vision Apps reservations/references; review EVM symbols/virtual Ethernet; port only missing kernel features; compare offline merged DT/ELF while retaining alternate boot | No overlap, resolvable phandles, load containment, required heap/address API. Do not boot Vision Apps if any fails |
| 5. Cores/shared memory | Apply matching DT/firmware together; check core start/TIOVX/targets/IPC/allocation/mapping/address/cache | RPMsg/TIOVX pass, matching CPU/DSP patterns, no repeated-allocation errors/crashes. Revert DT/firmware together on failure |
| 6. Minimal inference | One small file-input model compiled with pinned J721E Tools; one runtime initially; record input/preprocessing/precision/tolerance | Correct output plus delegated subgraph and C7x/MMA evidence. CPU-only result is not a pass |
| 7. Reproduce/expand | Cold boot/repeats; document versions/hashes/files/logs/install/recovery. Add cameras/display/ETHFW only if needed afterward | Same procedure reproduces inference and original boot recovery on a new test image |

## 9. Additional checks once board access is available

- **Unverified:** OS/kernel package/source/config. Collect /etc/os-release, uname -a, package versions, /proc/config.gz or matching /boot/config-*.
- **Unverified:** boot chain/effective DT. Record SPL/U-Boot/TIFS/DM versions/ABI via UART; collect actual DTB/DTBO/order, live DT or /sys/firmware/fdt and boot config. DTC comparison needs board DTS, J721E SoC/main/MCU DTSIs, IPC includes/overlays.
- **Unverified:** core/memory state. Collect remoteproc name/state/firmware, links, RPMsg, /proc/iomem, reserved-memory/CMA logs, heap/cdev lists. Determine actual contiguous/crossed DSP0/1 associations.
- **Unverified:** actual Debian ABI/acceleration. Compare library/symbol versions, firmware/runtime IDs, delegation/C7x profiles, accuracy, repeated-run memory usage with section 8 gates.

## 10. Recommendations and references

1. **Version decision:** obtain .07 product/distribution evidence first; until then use TI's J721E Linux.04/RTOS.06/Tools 11_02_04_00 baseline. [TI table](https://github.com/TexasInstruments/edgeai-tidl-tools/blob/master/docs/sdk_version_compatibility_table.md)
2. **Retaining Debian:** first test6.18 remoteproc/shared DMA-BUF on a boot-preserving SD. Estimate backport/allocator costs only for confirmed omissions. [TI heap history](https://git.ti.com/cgit/ti-linux-kernel/ti-linux-kernel/commit/?id=f22103162c771ddd47372b579682445e6dc8dd0e)
3. **DT/firmware:** prioritize integrating the matching Vision Apps map over BBAI64 board settings. Judge C66 straight/crossed associations by effective DT/ELF contracts. If relocating DDR, change linker/MMU/DT coherently. Evidence: local overlays/ELFs and rtos generators/maps.
4. **Proceeding:** require baseline IPC/shared-memory gates before C71x/MMA inference. Use actual boot console and [official board documentation](https://docs.beagleboard.org/boards/beaglebone/ai-64/) as the boot baseline.
