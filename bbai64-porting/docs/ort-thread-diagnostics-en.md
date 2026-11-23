# Single-Threaded ORT Comparison and Wait-Location Diagnosis

## Preparation status

Only the user-space probe and scripts were changed. Local C++/shell syntax checks passed. ARM64 linking and board execution remain Unverified; the board compiles with c++ as before. Keep kernel, firmware, DT, model, and RPMsg libraries unchanged. This experiment isolates possible ORT threading waits; it does not establish the cause or guarantee a fix.

BBAI64_ORT_SINGLE_THREAD=1 sets intra/inter-op=1, sequential execution, and spinning off for both CPU/TIDL sessions. At this stage, absent/0 retains prior behavior. BBAI64_STRACE=1 collects probe system calls inside timeout; it is off by default. PROBE_STAGE reports the single-threaded setting.

## 1. User upload

From the host project root:

```bash
scp bbai64-porting/rpmsg-work/thread-diagnostics.tar.gz beagle:~/
```

Preserve previous board files:

```bash
cd ~/bbai64-porting
test ! -e before-thread-diagnostics.tar && \
 tar -cf before-thread-diagnostics.tar src/ort-probe.cpp scripts/05-check-onnx-ep.sh scripts/06-diagnose-tidl-run.sh
```

Only if the backup succeeds:

```bash
tar -xzf ~/thread-diagnostics.tar.gz -C ~/bbai64-porting
cd ~/bbai64-porting
sha256sum -c staging/manifests/thread-diagnostics-SHA256SUMS
```

## 2. Run the single-threaded test once

```bash
cd ~/bbai64-porting
sudo env RPMSG_LIB_DIR="$PWD/rpmsg-work/diagnostic-lib" \
 bash scripts/07-check-ort-threading.sh \
 "$HOME/models/resnet18/model.onnx" "$HOME/models/resnet18/artifacts/" \
 "$HOME/models/resnet18/input.f32" 1.0
```

Wait for the 120-second probe limit and at most five additional seconds before forced termination. Compilation/log collection time is separate. Results remain under tidl-results/run-diag.XXXXXX. Check the last PROBE_STAGE and whether TIDL_subgraphRtInvoke/Running Graph/TIDL_BENCHMARK_OK appear. If it passes, skip strace and provide results. Single-thread success does not validate overall accuracy or performance.

## 3. Collect system calls only if it stalls at the same point

First check strace availability:

```bash
command -v strace
```

If absent, skip this optional test and provide results, or install it manually as follows. This installs a board user-space tool, not a required kernel change.

```bash
sudo apt-get update
sudo apt-get install --yes strace
```

With strace available, run once. ptrace-based observation can affect timing. Check free space because logs can grow. No reboot, remoteproc manipulation, or module loading is required.

```bash
cd ~/bbai64-porting
sudo env RPMSG_LIB_DIR="$PWD/rpmsg-work/diagnostic-lib" BBAI64_STRACE=1 \
 bash scripts/07-check-ort-threading.sh \
 "$HOME/models/resnet18/model.onnx" "$HOME/models/resnet18/artifacts/" \
 "$HOME/models/resnet18/input.f32" 1.0
```

Files named *.strace.PID in the result directory hold per-thread/process records. A final futex call alone does not prove deadlock. Distinguish the main thread from IPC workers and compare read/ioctl/poll/futex activity and termination. If tracing fails because of permissions or tools, report the error without weakening board security settings.

## 4. Return results and restore

Package each actual result directory. Preserve both if two tests were run.

```bash
sudo tar -czf "$HOME/ort-thread-result.tar.gz" \
 -C "$HOME/bbai64-porting/tidl-results" run-diag.ACTUAL_NAME
```

To restore prior behavior:

```bash
cd ~/bbai64-porting
tar -xf before-thread-diagnostics.tar
```

Alternatively, with this diagnostic revision, run05 without BBAI64_ORT_SINGLE_THREAD to use prior threading.07 always selects single-threaded execution. Unused new scripts do nothing; no system-configuration recovery or reboot is needed.
