# Step 04 IPC Failure Analysis and Action Plan — 2026-11-18

## Initial conclusion

**Verified:** Vision Apps IPC endpoint 13 is absent on MCU2_0 (MAIN R5F0_0,5c00000.r5f). Linux remoteproc running does not guarantee RTOS application initialization. The cause was not yet identified. Locate R5F application progress before changing kernel/DT again.

## Additional investigation

Read-only SSH collected uname, remoteproc name/state/firmware, RPMsg sysfs, firmware links/SHA256, and dmesg. [Raw results](../../docs/bbai64-survey/rpmsg-followup-20261118.log). No privileged commands, endpoint creation, remoteproc manipulation, or upload occurred.

- **Verified:** tidl2 runs; two C66x, C71x, and two MAIN R5F are running. MCU R5F remains attached.
- **Verified:** MAIN R5F0_0 virtio5 has only ctrl/ns, no port 13. Four other Vision Apps cores have13; none show21.
- **Verified:** /lib/firmware/j7-main-r5f0_0-fw points to bbai64-psdk-11.02/vx_app_rtos_linux_mcu2_0.out and matches SDK hash6f99b5497f75be958d59d845d782b0ffa1503eb22c75b9b4f895d641b61ea1c2. This does not validate live execution memory.
- **Verified:** user-read trace0 is empty. debugfs ls size 0 is not actual buffer length.
- **Verified:** SDK vision_apps/platform/j721e/rtos/ipc_trace.c uses the Ipc_Trace_printf buffer; appLogWrInit in rtos/common/app_init.c uses separate g_app_log_shared_mem. Ordinary application logs need not appear in trace0.

## Candidate causes and evidence limits

**Likely:** MAIN R5F0_0 stops or enters error handling before IPC service announcement. Its missing service and other cores' missing21 are consistent with incomplete initialization/synchronization. app_init.c calls appIpcInit, appLogCpuSyncInit with MCU2_0 as master, then appRemoteServiceInit. Missing21 alone does not prove separate failures on every core.

**Priority candidate, Unverified:** EVM ETHFW/board initialization. appMemInit precedes appEthFwInit, then appIpcInit. vision_apps/utils/ethfw/src/app_ethfw_freertos.c enables the J721E GESI flag and calls EthFwBoard_init. The deployed ELF contains ETHFW/GESI EEPROM error strings. EVM initialization is not assumed appropriate for BBAI64, but the exact stopping call is unproven. Sciclient, UDMA, MPU checks, and earlier initialization remain candidates.

RPMsg0.6.11 changes endpoint lookup failure to a warning. Its endpoint=0 fallback has not been validated for round trips and cannot create the missing R5F service. Treat that separately.

## Recommended order and stop conditions

1. **Prepare diagnostic MAIN R5F0_0 sources locally.** In an independent SDK copy, instrument Sciclient/UDMA/memory/ETHFW/IPC before/after using Ipc_Trace_printf. Use trace0 instead of UART, record failures, and retain memory map/resource table. This initially describes a design; no diagnostic firmware had been built/applied.
2. **Review noeth.** Confirm BUILD_ENABLE_ETHFW=no removes MCU2_0 ENABLE_ETHFW/link inputs. Preserve SDK/map and separately review UART/pinmux/EVM dependencies. Disabling ETHFW is not a guaranteed fix.
3. **After review, the user tests one image manually.** Preserve old files, use a separate name, do not arbitrarily stop/start remotely, establish network/SD recovery, and leave MCU R5F unchanged.
4. **Acceptance:** MAIN R5F0_0 endpoint 13, completed peer synchronization/required21 services, corrected04 without IPC errors. On failure, change only the path identified by trace.
5. **Then05:** same RPMsg library, remote-node creation/return, CPU comparison. No reason yet to requantize or rebuild the entire kernel. Investigate host-endpoint propagation if endpoint=0 breaks replies.

No additional repeated user command is needed now: another empty trace read/04 adds no evidence. Prepare diagnostic firmware/noeth configuration locally.

## Follow-up preparation complete

Marker patch, independent SDK copy tool, variant build script, and [host guide](../firmware-work/README-en.md) were prepared. Patch application/result comparison and shell syntax passed. Lengthy SDK copying/full compilation/linking had not started; no deployable ELF yet.

## Trace candidate built and reviewed

The user's ELF/map passed DDR LOAD containment/overlap, resource-table equivalence, trace layout, and marker checks. firmware-work/deploy-trace/ contains the candidate set. Hardware behavior remained Unverified; see [deployment/recovery](../firmware-work/deployment-trace-en.md).

## Diagnostic firmware results — 2026-11-18

User04-check-tidl-runtime.PjzpRS.log shows heap initialization success but missing MCU2_0 port 13/peer21 persists. No evidence points to a new kernel/model problem. The firmware observes the cause; reproducing the failure is not itself a failed fix.

Read-only SSH results are in docs/bbai64-survey/trace-firmware-result-20261118.log. Link/hash match the candidate and dmesg records12933488 bytes loaded, making simple deployment omission unlikely. The collected352-byte trace reaches:

```
BBAI64: after appLogGlobalTimeInit rc=0
BBAI64: before appSciclientInit
BBAI64: after appSciclientInit rc=0
BBAI64: bef
```

**Verified:** main/OS task/GTC/Sciclient were reached. The next complete marker is absent; code order identifies it as before appUdmaInit.

**Unverified:** whether UDMA or a later stage stalled.352 is a32-byte boundary ending mid-marker. j721e_mpu_cfg.c region6 makes DDR WB/WA cacheable. Trace0xa342bc00 is outside noncached IPC [0xa2000000,0xa2100000). Ipc_Trace_printf does not write back after stores. The visible tail can lag actual execution. The initial patch omitted visibility handling; do not conclude ETHFW or UDMA from this alone.

### Next response

1. Fix trace visibility first: consider SDK R5F writeback of changed data after each RTOS-task marker; separately verify APIs before main/OS initialization. Avoid broad MPU/cache disabling first.
2. Locally build/validate the improved diagnostic image, then let the user replace it. No new patch/ELF existed at this report stage. Use complete before/after/rc markers to distinguish UDMA/ETHFW/IPC.
3. Use noeth when ETHFW stopping is established; defer05/model rebuilding meanwhile.

The user authorized privileged reads for this trace/log, but sudo -n cat required a password. No authentication changes or password collection occurred. The user later supplied the detailed log. No remote system changes occurred.

## Cache-writeback diagnostic prepared

Patch0002 cleans changed R5F trace data using CSL/DSB. MCU2_0 build/link, ARM-call inspection, mocked write ranges, and ELF validation passed. deploy-trace-wb/ is ready with a [new guide](../firmware-work/deployment-trace-wb-en.md). Not yet applied/board-validated at this point; root-cause diagnosis continues.

## Cache-visible hardware results: narrowed to ETHFW

Read user-saved tidl-results/trace-wb/ over ordinary SSH into docs/bbai64-survey/trace-wb-result-20261118.log. Board link/hash match the new candidate.

```
BBAI64: after appSciclientInit rc=0
BBAI64: before appUdmaInit
BBAI64: after appUdmaInit rc=0
BBAI64: before appMemInit
BBAI64: after appMemInit rc=0
BBAI64: before appEthFwInit
```

**Verified:** Sciclient/UDMA/memory returned success. Execution reached immediately before appEthFwInit, without a return or appIpcInit entry marker. MCU2_0 still lacks13; other peers have13. ETHFW early initialization/OS startup already passed.

**Likely:** wait/error stop/exception inside appEthFwInit prevents IPC. Complete cache-visible markers are stronger evidence than the old truncated trace. Exact internal call/error remains Unverified; incompatible EVM GESI/board initialization is a candidate, not established. Linux running may not detect this state.

### Next recommendation

Build noeth with BUILD_ENABLE_ETHFW=no and BUILD_MCU_BOARD_DEPENDENCIES=yes, keeping SDK/map/peers/markers/writeback. Retain the runtime CPU list. Do not default to noboard, which also disables video/display; isolate ETHFW's effect.

After reboot require no appEthFwInit marker, after appIpcInit rc=0, synchronization/remote-service before/after, and13/21. Narrow later stalls by the last marker. Run05 only after 04 is IPC-error-free. Successful noeth communication implicates the ETHFW path, not necessarily a particular GESI function.

MCU2_0 ETHFW CPSW virtual Ethernet is disabled. Check interaction with SSH networking before applying and retain SD recovery; do not guarantee every Linux network device is unaffected. At this analysis stage no new noeth build/upload/remote change occurred.

## Noeth candidate prepared

An independent sdk-noeth with trace/cache patches built MCU2_0 using ETHFW=no/MCU_BOARD_DEPENDENCIES=yes. Peers unchanged. Only trace-address relocation differs in the resource table; DDR/overlap/markers/cache calls/ETHFW removal checks passed. deploy-noeth/ and a [user guide](../firmware-work/deployment-noeth-en.md) are ready. No kernel build/upload/board change; runtime behavior still Unverified then.

## Noeth hardware success and05 prerequisites

The user reported04 success (04-check-tidl-runtime.4ilLBl.log). Ordinary SSH checked saved trace, current RPMsg, firmware hash, and model files; see docs/bbai64-survey/noeth-success-20261118.log. Root-only04 details were not read.

**Verified:** noeth hash, IPC rc=0, synchronization/remote-service after markers, and ports13/21 on C71x/two C66x/two MAIN R5F. ETHFW exclusion bypassed the earlier blocker;05 prerequisites are met. Exact ETHFW failure and actual C71x/MMA inference remain Unverified.

User command:

```bash
cd ~/bbai64-porting
sudo env RPMSG_LIB_DIR="$PWD/rpmsg-work/lib" \
 bash scripts/05-check-onnx-ep.sh \
 "$HOME/models/resnet18/model.onnx" \
 "$HOME/models/resnet18/artifacts/" \
 "$HOME/models/resnet18/input.f32" 1.0
```

1.0 is a functional absolute-error tolerance for this quantized model, not accuracy approval. Model/artifacts/input exist; input.f32 is602112 bytes. Complete hashes were not rechecked in this inspection.

TIDL_BENCHMARK_OK plus remote-subgraph intervals passes CPU comparison/TIDL-path checks. The script then deliberately reports Unverified pending MMA evidence; inspect details rather than treating that summary as failure. Final acceleration validation requires same-run C71x/MMA evidence. For timeout/remote creation/numeric failure, investigate logs without repeating. Board inference is user-executed.

## Interrupted05 logs

The attachment is05-check-onnx-ep.JEIEur.log while the summary names5cKoUM; do not assume the same execution. Original: docs/bbai64-survey/step 05-JEIEur-user.log.

**Verified:**49/49 nodes form one TIDL subgraph; heap/IPC/host TIOVX initialization completed. No TIDL_BENCHMARK_OK/output-error/remote-completion evidence. Unused-initializer warnings remove unnecessary model data and are not direct failures. Signal15 is SIGTERM, consistent with timeout 120s but not proof of its sender; distinguish the separate Ctrl-C report. Without stage markers the waiting API is unknown. Buffered stdout can reorder visible messages.

**Likely candidate:** endpoint=0 fallback disagrees with TIOVX reply-port propagation. rpmsg-work/source/src/rpmsg_char.c returns0 on negative lookup; app_ipc_linux_rpmsg_char.c:381 stores local_endpt; tivx_ipc.c:281 ownIpcGetHostPortId forwards it; vx_obj_desc.c uses host_port_id in shared descriptors/IPC. Successful open alone does not establish a valid return path. No additional privileged log reads were made.

After interruption, ordinary SSH observed no ort-probe/test-timeout process. Default endpoint src values were1024, and1025 for service21. See docs/bbai64-survey/step 05-endpoint-check-20261118.log. These are default endpoints, not newly created in-flight ones. Earlier blanket interpretation as missing sysfs attributes must be narrowed: dynamic src may retain RPMSG_ADDR_ANY(-1). Kernel src_show exposes chinfo.src while open creates another endpoint, so compare requested and allocated addresses.

### Minimum next work

1. Obtain latest5cKoUM to distinguish runs; defer05 repetition/requantization/kernel/DT/firmware changes.
2. Add immediate CPU/TIDL session/Run/benchmark markers and distinguish timeout/Ctrl-C.
3. Log requested/sysfs/returned addresses. If needed review explicit local allocation/correct return with kernel collision checking, cleanup, and cross-process collisions; never replace0 with an arbitrary constant.
4. Prioritize user-space compatibility if wrong reply-port propagation is confirmed. If a correct port still stalls, examine C71x target/descriptors/cache/firmware.

This was analysis/planning; no new probe/library changes, upload, or board run yet.

### Latest5cKoUM supplied

Saved docs/bbai64-survey/step 05-5cKoUM-user.log. Same pattern as JEIEur:49/49 delegated, initialization passed, ten endpoint=0 warnings, SIGTERM, no completion/comparison/benchmark. Repetition supplies no evidence of a one-off parser error. Reply-port mismatch remains a priority candidate, not confirmed cause. Signal sender/wait API/actual address remain unknown. Next add stage/address diagnostics in user space without kernel/DT/firmware rebuild, with manual deployment. No further change/run at this stage.

## User-space05 diagnostics ready

Implemented immediate session/Run/benchmark markers, address logging, and timeout/SIGINT classification while retaining address semantics. ARM64 library build/exported-symbol equivalence and shell/host-probe syntax passed. ARM64 probe linking/hardware remain Unverified. [Guide](../rpmsg-work/step05-diagnostics-en.md) and step 05-diagnostics.tar.gz provided; no board upload/run.

## bvJdkv: TIDL session wait and endpoint-return defect confirmed

Original saved in docs/bbai64-survey/step 05-bvJdkv-user.log.

**Verified:** CPU session completes within 549ms; before tidl_session is the last marker, without after. Ort::Session(target) exceeds120 seconds; CPU/TIDL Run and comparison are not called. Wrapper124 establishes timeout.

**Verified:** all ten requests use4294967295(ANY); created-endpoint sysfs src is-1. The library returns0. The attribute exists but exposes ANY. virtio_rpmsg_bus.c allocates ANY with id_min=1024, so actual allocated address cannot be0. Individual actual values were not measured.

Tracing local_endpt storage through ownIpcGetHostPortId and shared host_port_id establishes **a wrong reply-port defect and a likely cause of this session wait**. Fixing it alone is not proven sufficient for inference.

Duplicate cleanup/invalid-handle errors occur after SIGTERM. Do not treat them as the earlier stall's direct cause. Separate cleanup reentrancy/handle problems remain possible, but fix the reply port first.

### Initial implementation direction

Prefer user-space compatibility without kernel changes: review replacing ANY with an explicitly reserved local address and returning the successful address. Account for uint16 host_port_id limits, reserved ranges, cross-process/same-rproc collisions, reservation at open rather than device creation, and cleanup/retry. Do not substitute1024 or assume PID-based uniqueness. Fail explicitly on unsupported/mismatched addressing rather than fallback0.

Prepare local patch/ARM64 build/offline checks and a manual guide. Verify valid request/query/return, after tidl_session, after tidl_run, TIDL_BENCHMARK_OK. No compatibility patch, system changes, model changes, or rerun yet at this point.

## Rechecking an ETHFW-disable request

Read-only SSH reconfirmed noeth link/hash/success trace. No duplicate build/upload occurred. [ETHFW impact](ethfw-role-and-disable-en.md). The local-endpoint defect is separate and cannot be described as fixed by reapplying noeth.

## Final compatibility approach: before tidl3 build

Reviewing explicit reservation showed open-time allocation and complicated cdev cleanup on failure. Instead minimally fix kernel src_show, which already has the actual address. This supersedes the user-space-first proposal. No rootfs regeneration; the user builds a new matching kernel/module set.

0004 reads ept->addr under ept_lock for open endpoints, retaining requests for unopened ones and automatic collision handling. Clean application/result comparison, previous DMA combined changes, diff/shell checks passed. out-tidl3/.config ready; no compile/link/new binary/board change. [Build guide](../patches/tidl3-build-start-en.md) and scripts/build-tidl3-kernel.sh supplied. Keep noeth/diagnostic-lib; validate reply address/session/Run on the new kernel. Full inference remains Unverified.

## User completed tidl3 build; deployment reviewed

Verified modules_install/depmod/package completion, staging checksums, and tidl3 vermagic. One cc33xx debugfs FORTIFY warning remains. Read-only SSH checked tidl2 boot/free space/noeth hash. [Deployment guide](tidl3-deployment-en.md) covers matching image/modules, separate default entry, tidl2 recovery, and04/05. Codex did not build the kernel or change/upload to the board.

## SmOQ5M after tidl3: address fixed, failure moved into Run

Original docs/bbai64-survey/step 05-SmOQ5M-user.log; compared user04 success with05 details.

**Verified:** IPC raw/returned1026 and service raw/returned1027; the old-1/0 defect is gone. Equal endpoint numbers on distinct rprocs are not inherently collisions because allocation is per virtio device.

**Verified:** after tidl_session2689ms and after cpu_run2934ms precede before tidl_run without return. Exit124 establishes120-second timeout. Session/CPU inference now pass, demonstrating progress but not complete acceleration. Comparison/benchmark were not reached.

**Unverified:** exact target.Run location. First EP Run may include deferred remote creation/graph verification; these markers do not prove MMA itself stalled. tidl_rt_ovx.c has separate vxVerifyGraph/vxProcessGraph calls; present logs do not distinguish them.

Next inspect EP/runtime debug controls and collect same-run C71x state/trace/shared logs immediately afterward. Treat empty traces with cache visibility in mind. Descriptors, buffer addresses/cache, target errors, and artifacts remain candidates without unsupported ranking. Do not repeat kernel/DT/firmware patches/model recompilation. Respect separate authorization for root-only SSH reads. No further package change then; retain tidl3/noeth/diagnostic-lib while narrowing Run.

## run-diag.YQhftv findings

Safely extracted tidl-run-diag-result.tar.gz under docs/bbai64-survey/run-diag-review/ and verified SHA256.98HdsU shows graph creation/verification, network copy to C7x heap, and TIDL_subgraphRtCreate done—strong evidence of remote graph preparation during session creation. Timeout follows CPU Run and before tidl_run; **no TIDL_subgraphRtInvoke or Running Graph message appears**. Prioritize ORT Run to EP Invoke/runtime entry rather than assuming vxProcessGraph/MMA stalls. Library logs do not fully instrument every path; a call stack is needed for exact attribution.

Shared-log snapshots succeeded. C71x registration/initialization/boot echo appeared, without an explicit processing error tied to this Run. MCU2_0 Sciclient/DP errors belong to boot history and are not established as the current cause.

Next compare a probe with both sessions intra/inter-op1, sequential, and spinning disabled. This tests an ORT-threading hypothesis, not a confirmed cause/fix. Prepare optional user strace/stacks to distinguish futex/IPC read/ioctl waits. Defer kernel/firmware/model rebuilds; no new candidate had yet been written at this analysis point.

## ORT comparison candidate ready

Implemented BBAI64_ORT_SINGLE_THREAD=1 for both sessions.07 selects it and reuses06 collection. Optional BBAI64_STRACE=1 records calls inside timeout. C++/shell checks/package hashes ready; ARM64 linking/hardware Unverified. No upload/run. [Guide](ort-thread-diagnostics-en.md)

## run-diag.fddW6r: actual single-threaded inference passed

Extracted ort-thread-result.tar.gz under docs/bbai64-survey/ort-thread-review/ and verified checksums. FFZxxo shows threads1/sequential/spin-off, TIDL_subgraphRtInvoke, vxProcessGraph/output-copy completion, and TIDL_BENCHMARK_OK. max_abs_error0.722227 closely matches host0.722229. Run markers3234–3240ms imply approximately6ms for this single invocation, not a precise performance benchmark.

Same-run layer profiling totals2473597 cycles, with subgraph proc_start/end and output return. This is stronger remote TIDL/C71x evidence than service registration alone. Direct MMA instruction/counter evidence and repeat stability remain. Exit2 reflects the script's conservative final Unverified policy, not a probe failure.

The combined threading changes bypassed the stall. Without separating intra-op/inter-op/sequential/spin effects, do not assert an ORT deadlock. Preserve working settings; no strace repetition/system rebuilds needed now. Next establish defaults/repeats/numeric checks and grade C71x/MMA evidence. Tensor-swap warnings used copy/reformat successfully and are not failures by themselves.

## Working defaults and repeats prepared

Default single-thread/sequential/spin-off added.08 performs warm-up1+measured10, compares every output/processing interval, and summarizes drift/latency.05 success now means functional validation, distinct from MMA proof. Syntax passed; board not run at preparation. [Guide](repeat-validation-en.md)

## Repeat validation complete

HcuRol/Os1IYF:45 checksums valid; warm-up1+10 measured runs all pass CPU comparison/TIDL benchmark. Output drift 0, maximum error 0.722227, mean 5.71518ms. Repeated functional success remains distinct from endurance/direct MMA validation. Updated status is in porting-reassessment-en.md.
