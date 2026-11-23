# BBAI64 TIDL Porting Feasibility and Quantization Reassessment

## Conclusion at the initial reassessment stage

**Recommendation: continue conditionally while retaining Debian.** The official version combination and host inference are Verified. Changes progressively established DMA, IPC, and TIDL session creation. The remaining failure was narrowed to the first TIDL Run, but graph verify/remote create/process had not been distinguished. Debian13 alone is not evidence of impossibility; neither is there evidence that this equals an officially supported or production-ready configuration.

Choose the next component to modify after one detailed diagnostic run. Runtime/C71x rebuilds are authorized for consideration, not for rebuilding everything without observations.

## Key history and status at reassessment

- Backported the DMA heap exporter/TI address interface to establish the host-buffer path.
- Disabled ETHFW on MCU2_0 after EVM initialization stalled, enabling IPC/synchronization/remote services and04.
- tidl3 fixed RPMsg actual-address reporting:1026/1027 replaced raw=-1/return0; TIDL session and CPU Run passed.
- SmOQ5M timed out120 seconds after before tidl_run. No CPU/TIDL comparison or MMA success evidence yet.

Evidence: rpmsg-failure-analysis-en.md, docs/bbai64-survey/step 05-SmOQ5M-user.log, and reassessment-board-20261118.log.

## Versions and Debian-specific limitations

| Area | Status | Evidence and limitations |
|---|---|---|
| RTOS 11.02.00.06/Linux 11.02.00.04/TIDL11_02_04_00 | Verified | TI J721E component matrix; host-image source commit bb029fb79929e0fc0c2c13d2d40b13237eabbca1 |
| Debian13.6/GLIBC 2.41/r47-tidl3 | Verified, partly from prior collection | Current SSH confirmed tidl3/GLIBC 2.41; Debian point release comes from previous board records |
| User-space ABI | Executed paths Verified | TI ORT 1.15 loading/session creation/CPU Run passed. Board libvx_tidl_rt/ORT hashes match local files; not all lazy symbols/paths are covered |
| Kernel DMA/IPC | Partially Verified | Allocation, address query, endpoint reporting, initialization pass. Actual C71x-consumed addresses/coherence/descriptor round trips remain Unverified |
| SYSFW resources/boot chain | Outstanding checks | Boot chain retained. Sciclient success does not establish identical DMA/IRQ/MMA assignments to SDK |
| C71x target/TIDL/MMALIB | Coherent-release evidence; execution Unverified | SDK firmware used, but first Run incomplete. Exceptions/heaps/target creation/buffer visibility need investigation |

Official documentation assumes Processor SDK Linux. The important differences are TI kernel UAPI, memory/cache behavior, resources, and firmware/runtime coupling—not the distribution name alone. OS migration or mixing TIDL versions is not the default approach.

## Independent model/quantization revalidation

On2026-11-18, reran the pinned bbai64-tidl:11_02_04_00-j721e image (a8a10cfd1bfb) with originals mounted read-only and a separate artifacts copy. Existing outputs were not overwritten. onnx.checker also passed.

| Check | Result |
|---|---|
| ORT/target | 1.15.0/J721E, TIDLExecutionProvider present |
| Board model/input/net/io/meta hashes | All match the local ready set |
| Regenerated official preprocessing | Byte-identical to input.f32 |
| Input | RGB loader, NCHW[1,3,224,224], little-endian float32,602112 bytes |
| CPU/host-TIDL outputs | [1,1000], all finite |
| Maximum absolute error/RMSE | 0.72222900390625/0.1836877697153177 |
| Top1 index | CPU895/TIDL895 |
| Difference from stored CPU/TIDL outputs | 0.0/0.0 |

Script: tidl/scripts/reassess-resnet18.py. Log: tidl/logs/reassessment-host.log. Measurements/hash comparison: tidl/reassessment/results.json and board-hash-comparison.json. Official basic DatasetLoader/PreProcess and saved configuration were used. Compilation used8-bit, calibration_frames=2, iterations=5. The official configuration and original compile log are preserved.

**Assessment:** wrong deployment, preprocessing mismatch, or quantized artifacts that cannot run even on the host are inconsistent with these observations. Requantization is not the first action. Two calibration frames/one compared input do not establish accuracy. Host emulation does not guarantee C71x code generation, MMA, or board memory requirements. Tolerance1.0 is functional-test policy, not an accuracy acceptance criterion.

Application-level accuracy requires representative calibration/evaluation data and agreed accuracy-loss criteria. Do not invent dataset-wide accuracy or arbitrary product thresholds in this analysis.

## Next diagnostics and decision gates

The user runs once with TIDL_RT_DEBUG=1/EP debug_level=1 following the [guide](run-diagnostics-guide-en.md), collecting before/after C71x trace/shared logs/dmesg. Scripts do not install, manipulate remoteproc, or change reader indices. The runtime contains TIDL_RT_DEBUG and SDK lib_init parses it. Shared-log structure comes from app_utils/utils/console_io/include/app_log.h:16×16KiB at app_mem_map.h0xac000000/0x40000. Check the live reservation before read-only snapshots. Collection itself remained board-Unverified at this preparation stage.

- **Continue:** a wait boundary and fixable cause are identified in verification/copy/processing.
- **Proceed conditionally:** more runtime/C71x markers are needed and matching source/compiler/memory validation/recovery can be obtained. Rebuild only the required isolated component.
- **Recommend deferral:** essential source/tools/observation/recovery are unavailable, or changes conflict with retaining Debian/current kernel family. Do not generalize this to OS impossibility.

Initially this was the second case. Narrow with existing logs first. Before graph verification, inspect target registration/descriptors/IPC; after verification, inspect C71x errors, buffer addresses/cache, and MMA/memory resources. Recompile only if errors implicate input/artifacts, retaining the original set. On success, correlate numeric output and same-run C71x/MMA profiles, then separate diagnostics and document reproducible patches.

## Maintenance cost and outstanding work

Maintain four out-of-SDK kernel patches, noeth configuration, isolated TI ORT 1.15, and diagnostic libraries. Debian updates require UAPI/module/boot regression checks. DMA/RPMsg changes and the memory map are enduring implementation requirements; temporary logs should be separate from final deployment. At this reassessment stage, performance, accuracy, endurance, reboot repeatability, and MMA offloading were not claimed complete.

## References

- [TI J721E11.02 components and Linux/TIDL/MMALIB versions](https://software-dl.ti.com/jacinto7/esd/processor-sdk-rtos-jacinto7/11_02_00_06/exports/docs/psdk_rtos/docs/user_guide/sdk_components_j721e.html)
- [TI J721E TIDL11.02 release notes](https://software-dl.ti.com/jacinto7/esd/processor-sdk-rtos-jacinto7/11_02_00_06/exports/docs/c7x-mma-tidl/TIDeepLearningProduct_ReleaseNotes.html)
- Local SDK: lib_init/verify_graph_tidl_tiovx/vxProcessGraph in c7x-mma-tidl/arm-tidl/rt/src/tidl_rt_ovx.c; app_utils log structures; Vision Apps J721E app_mem_map.h.

## Hardware follow-up: a functional porting path established

The fddW6r single-thread test completed TIDL Run, CPU comparison, benchmark, and layer-cycle output, superseding the earlier incomplete-Run status. This supports functional inference while retaining Debian; proceed to repeats. Exact threading cause, application accuracy/performance/endurance, and direct MMA evidence remain open. Working defaults and a [repeat guide](repeat-validation-en.md) were prepared; the new repeat probe had not yet run at that point.

## Repeated hardware execution: run-diag.HcuRol

Extracted tidl-repeat-result.tar.gz to docs/bbai64-survey/repeat-review/ and checked45 collected-file hashes. Os1IYF shows one warm-up plus ten measured invocations, each with TIDL_BENCHMARK_OK and advancing subgraph intervals. Exit0; worst_abs_error=0.722227; drift_from_first=0. Excluding warm-up, target.Run mean 5.71518ms, min 5.32909ms, max 8.4768ms. These short-run observations include debug, host copies, and scheduling, not pure MMA latency or endurance metrics.

**Updated assessment:** repeated functional ResNet18 TIDL inference while retaining Debian is now Verified on hardware. The old Run stall did not recur with the pinned ORT settings. Isolating individual threading causes, multiple-input accuracy, endurance/reboot stability, and direct MMA metrics remain. No evidence justifies another kernel/firmware rebuild. Next pin hashes/settings and installation instructions, then correlate SDK target profiles/MMALIB-call evidence. Keep established functionality distinct from incomplete product validation.
