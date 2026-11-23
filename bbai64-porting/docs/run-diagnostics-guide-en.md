# User Guide to Detailed TIDL Run Diagnostics

Keep tidl3, noeth firmware, diagnostic-lib, and the existing model. No new kernel/firmware build or requantization is needed. Host model revalidation is complete; board execution is performed manually by the user.

## Upload and preserve recovery files

Host:

```bash
cd /home/corsair/Documents/sdk/ti_sdk_lab
scp bbai64-porting/rpmsg-work/run-diagnostics.tar.gz beagle:~/
```

Board:

```bash
cd ~/bbai64-porting
# If a backup exists, inspect it first; do not overwrite it.
test ! -e run-diagnostics-before.tar && \
 tar -cf run-diagnostics-before.tar src/ort-probe.cpp scripts/05-check-onnx-ep.sh
```

Only after backup succeeds:

```bash
tar -xzf ~/run-diagnostics.tar.gz -C ~/bbai64-porting
cd ~/bbai64-porting
sha256sum -c staging/manifests/run-diagnostics-SHA256SUMS
```

All checks must be OK. The existing RPMsg diagnostic-lib is required and is not replaced by this bundle.

## Run diagnostics once

```bash
cd ~/bbai64-porting
sudo env RPMSG_LIB_DIR="$PWD/rpmsg-work/diagnostic-lib" \
 bash scripts/06-diagnose-tidl-run.sh \
 "$HOME/models/resnet18/model.onnx" "$HOME/models/resnet18/artifacts/" \
 "$HOME/models/resnet18/input.f32" 1.0
```

The script enables TIDL_RT_DEBUG=1 and EP debug_level=1 and collects before/after C71x state/trace, dmesg, RPMsg devices, and read-only SDK shared-log snapshots. It checks the live-DT reservation before opening /dev/mem with O_RDONLY/PROT_READ and never changes reader indices. If /dev/mem or trace access is blocked, it records errors without modifying settings or bypassing restrictions. It does not run SDK app_remote_log, which can change reader indices and file-I/O state.

Wait for the 120-second probe limit and up to five seconds before forced termination. C++ compilation and before/after collection are separate. The script reports tidl-results/run-diag.XXXXXX and attempts after-collection even on a failed probe. Ctrl-C can interrupt collection; normally wait for completion.

## Results to provide

```bash
# Replace with the directory name reported by the command.
sudo tar -czf "$HOME/tidl-run-diag-result.tar.gz" -C "$HOME/bbai64-porting/tidl-results" run-diag.ACTUAL_NAME
```

Provide the bundle, or the detailed05 log and C7x-related content in after/shared-log/cpu-*-ring.txt. These are non-atomic snapshots of memory that may change during execution; correlate timestamps/indices to distinguish retained historical logs. An empty C71x trace is not evidence of normal operation; cache visibility may be limited.

Find the last completed stage among graph creation, verification, input copy, and vxProcessGraph. Only if existing logs are insufficient, instrument the relevant runtime calls based on this result. Expand firmware diagnostics if remote creation or C71x exceptions point there. Do not rebuild kernels, requantize, or extend timeouts without evidence.

## Revert

```bash
cd ~/bbai64-porting
tar -xf run-diagnostics-before.tar
```

Restoration returns05 to the previous probe. The added collector is inert when not invoked and may remain. No system settings, modules, or firmware are changed, so no reboot is required. Codex did not upload or execute diagnostics remotely.
