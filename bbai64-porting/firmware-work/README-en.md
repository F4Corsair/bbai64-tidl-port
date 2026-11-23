# Prepare and Build MAIN R5F0_0 Diagnostic Firmware

Initial status: **diagnostic patch/build helpers prepared; full compilation, linking, and board execution Unverified**. The original SDK and board were unchanged.

## Purpose

MAIN R5F0_0 is running but lacks IPC endpoint 13, so application initialization is not established. Without UART, write before/after markers directly to the IPC trace buffer to determine whether EVM board initialization, particularly ETHFW, blocks progress.

The SDK also offers BUILD_MCU_BOARD_DEPENDENCIES=no. sdk_builder/vision_apps_build_flags.mak:242 recommends it for non-EVM boards or HLOS-controlled peripherals. Keep variants separate to avoid changing every condition at once:

| Variant | ETHFW | MCU board dependencies | Purpose |
|---|---|---|---|
| trace | yes | yes | Add markers to existing settings; try first |
| noeth | no | yes | Use if trace identifies ETHFW initialization failure/wait |
| noboard | no | no | Consider if further EVM initialization blocks progress; camera/display functionality changes |

No remote stop/start or automatic installation is provided. Only the MAIN R5F0_0 candidate changes; MCU R5F remains untouched.

## Prepared files

- 0001-mcu2-0-init-trace.patch: before/after markers for main/task entry, OS, GTC, Sciclient, UDMA, memory, ETHFW, IPC, core synchronization, and remote services. Record rc for key returning calls. Preserve assertions/order.
- modified/: two patched source files; do not copy them into the original SDK.
- prepare.py: independently copies approximately8GiB of SDK and patches it without hard links. Redirects internal absolute symlinks and records external/broken links.
- build.sh: selects MCU2_0 only, prevents cross-variant object reuse, and rejects valid symlinks to external files.
- source-SHA256SUMS/offline-validation.log: source hashes and patch-check results.

## Duration and verified scope

TI Arm Clang **4.0.4.LTS runs locally**; patch application/result comparison and script syntax passed. Full firmware compilation/linking had not been performed at this point. The commands below are a reproduction starting point, not a build-success claim.

Copying alone reads/writes about8GiB. Builds may take minutes or longer if dependencies require rebuilding; duration is unmeasured. Allow at least15–20GiB separate from the SDK, plus space for each variant. The lengthy copy/full build had not been started at this preparation stage.

## Host procedure

Start at the project root. Requirements: Linux x86_64, Python 3, GNU make, patch, and the SDK's R5F compiler—not ARM64 Linux GCC. Prefer the SDK's Ubuntu22.04 host environment; stop and record host-library errors. No TI repository download or installer execution is required.

```bash
cd /home/corsair/Documents/sdk/ti_sdk_lab
command -v python3 make patch
sdk_original/ti-cgt-armllvm_4.0.4.LTS/bin/tiarmclang --version
hashes=$(realpath bbai64-porting/firmware-work/source-SHA256SUMS)
(cd sdk_original && sha256sum -c "$hashes")

# This copies the full SDK. The destination must not already exist.
python3 bbai64-porting/firmware-work/prepare.py \
  sdk_original bbai64-porting/firmware-work/sdk-trace

cat bbai64-porting/firmware-work/sdk-trace/bbai64-copy-links.txt

# Inspect commands in the independent copy; make -n may create internal metadata.
set -o pipefail
bash bbai64-porting/firmware-work/build.sh \
  bbai64-porting/firmware-work/sdk-trace trace dry-run \
  2>&1 | tee bbai64-porting/firmware-work/trace-dry-run.log

# Run only after a clean dry run. Foreground local build; no board access.
JOBS=2 bash bbai64-porting/firmware-work/build.sh \
  bbai64-porting/firmware-work/sdk-trace trace build \
  2>&1 | tee bbai64-porting/firmware-work/trace-build.log
```

Change the initial cd on another host. For noeth, prepare a fresh sdk-noeth destination, then pass sdk-noeth noeth to build.sh; use the same pattern for noboard. Do not copy out/lib/obj from another variant.

**Stop conditions:** source hash mismatch, external links, compiler failure, missing header/archive, No rule to make target, or link failure. build.sh does not expand automatically to make sdk. If supplied PDK/app_utils/TIOVX archives do not link, inspect the log first; do not rebuild the entire SDK or substitute unrelated libraries. -B forces regeneration of changed common libraries/executables and may increase work through dependencies.

## Offline checks after building

Find the candidate below. Actual final directory names can depend on SDK configuration.

```bash
find bbai64-porting/firmware-work/sdk-trace/vision_apps/out \
  -name 'vx_app_rtos_linux_mcu2_0.out' -type f -print
```

Do not install merely because linking succeeded. Compare ELF/link map against staging/firmware/vision_apps_evm/vx_app_rtos_linux_mcu2_0.out and applied DT reservations. Check MCU2_0 LOAD containment, resource-table/trace addresses and sizes, and overlap with other cores. Verify CPU_mcu2_0, FREERTOS, release, and ENABLE_ETHFW in build logs. Until reviewed, this is a **candidate awaiting deployment approval**. Keep the board's GP/HS signing scheme.

## Subsequent user-performed testing

Finalize deployment commands only after memory-map review. This guide does not install an unreviewed ELF. Preserve working firmware and apply one candidate at a time. Another PC must be able to edit the SD if SSH fails; defer without that recovery route when UART is unavailable.

After reboot, confirm remoteproc5/name still identifies5c00000.r5f, then read trace0/RPMsg. Interpret the last BBAI64 before/after pair:

- ETHFW before only or failing after rc: evidence for noeth.
- Before IPC: inspect that stage's resources/board dependencies.
- cpu_sync before only: check participating cores and shared synchronization/log memory.
- Through remote_service: check endpoints13/21, then04.
- No markers: investigate pre-main execution, loaded image, trace address/cache visibility. Missing trace alone does not prove no execution.

The initial diagnostic uses SDK Ipc_Trace_printf without a cache-visibility fix. TRACE is an Unverified diagnostic aid, not a health guarantee. Run05 only after 04 passes without IPC errors.

## Follow-up: trace candidate built and reviewed

The user's ELF/map passed DDR LOAD/overlap, resource-table, trace-layout, and marker checks. deploy-trace/ contains the candidate set. Board behavior remained Unverified; see the [manual deployment/recovery guide](deployment-trace-en.md).

## Follow-up: cache-writeback variant ready

Patch0002 cleans updated R5F trace data with CSL and DSB. MCU2_0 build/link, ARM-call inspection, mocked range tests, and ELF validation passed. The set is deploy-trace-wb/; see the [new guide](deployment-trace-wb-en.md). Not yet applied/tested on the board at this stage; root cause remained under investigation.

## Follow-up: noeth candidate ready

An independent sdk-noeth copy with trace/cache patches built MCU2_0 using ETHFW=no and MCU_BOARD_DEPENDENCIES=yes. Peers remain unchanged. Except for the relocated trace address, the resource table is identical; DDR/overlap, marker/cache-call, and ETHFW-removal checks passed. deploy-noeth/ and the [manual guide](deployment-noeth-en.md) are available. No kernel build or board upload/change was performed; hardware behavior remained Unverified at this stage.
