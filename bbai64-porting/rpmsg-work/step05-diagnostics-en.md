# Step 05 User-Space Diagnostic Variant

## Preparation status

Not uploaded; board execution Unverified. Without changing kernel, firmware, DT, or model, record:

- PROBE_STAGE: elapsed time before/after CPU session, TIDL session, CPU Run, TIDL Run, and benchmark calls; output buffering disabled.
- RPMSG_DIAG request: rproc, endpoint name, requested local/remote addresses.4294967295 means ANY.
- RPMSG_DIAG src: sysfs path and raw value or read error.
- RPMSG_DIAG returned: local endpoint returned to the SDK.
- PROBE_WRAPPER exit_code: distinguish timeout 124, SIGINT130, etc. A process still running after 120 seconds is forcibly terminated five seconds later. SIGKILL137 alone cannot distinguish timeout escalation from an external kill.

**The existing endpoint=0 fallback is retained.** This is a diagnostic library to investigate return-address mismatch, not a fix. It does not assign arbitrary fixed addresses.

ARM64 library build, exported-symbol/SONAME equivalence, script syntax, and host g++ probe syntax checks passed. ARM64 probe linking/execution was not performed because ARM64 g++ was unavailable on the host. The board compiles with c++ as before. One upstream TI unused-variable warning remains.

## 1. Manual upload

```bash
cd /home/corsair/Documents/sdk/ti_sdk_lab
scp bbai64-porting/rpmsg-work/step05-diagnostics.tar.gz beagle:~/
```

The bundle contains only updated scripts/05-check-onnx-ep.sh, src/ort-probe.cpp, separate rpmsg-work/diagnostic-lib, and checksums. Preserve rpmsg-work/lib and staging/lib.

## 2. Back up the previous test files and extract

```bash
cd ~/bbai64-porting
# Stop and inspect any existing backup.
test ! -e step05-before-diagnostics.tar && \
 tar -cf step05-before-diagnostics.tar scripts/05-check-onnx-ep.sh src/ort-probe.cpp
```

Proceed only after backup succeeds; do not automatically continue on failure.

```bash
tar -xzf ~/step05-diagnostics.tar.gz -C ~/bbai64-porting
cd ~/bbai64-porting
sha256sum -c rpmsg-work/step05-diagnostics-SHA256SUMS
```

All checksums must pass. No reboot or04 repeat is needed. Check for a previous running test; do not run two inference processes concurrently.

## 3. Execute diagnostics

```bash
cd ~/bbai64-porting
sudo env RPMSG_LIB_DIR="$PWD/rpmsg-work/diagnostic-lib" \
 bash scripts/05-check-onnx-ep.sh \
 "$HOME/models/resnet18/model.onnx" \
 "$HOME/models/resnet18/artifacts/" \
 "$HOME/models/resnet18/input.f32" 1.0
```

If it stalls, wait for the120-second timeout and up to five seconds of termination grace. This limit applies to the probe, not preceding C++ compilation. Ctrl-C is classified as manual interruption. Read and provide the actual detailed log reported by the script.

```bash
# Replace with the actual reported filename.
sudo cat tidl-results/05-check-onnx-ep.ACTUAL_NAME.log
```

src raw=-1 with returned endpt=0 strongly suggests a mismatch between ANY and actual return-address lookup. It still does not measure the actual kernel endpoint address, so confirmation needs more evidence. A final before tidl_session points to session initialization/remote-node creation; before tidl_run points to Run. A CPU-stage stall does not establish an RPMsg cause. Analyze logs rather than repeating failed/interrupted runs.

## Restore

```bash
cd ~/bbai64-porting
tar -xf step05-before-diagnostics.tar
```

Set RPMSG_LIB_DIR back to rpmsg-work/lib to use the previous library. diagnostic-lib need not be deleted because it does not replace system libraries. No board settings or firmware are changed in this step.
