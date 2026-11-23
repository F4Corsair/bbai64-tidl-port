# Pin the Working Settings and Validate Repeated Inference

## Changes and validation status

The working ORT configuration—intra/inter-op=1, sequential execution, spinning off—is now the probe default. BBAI64_ORT_SINGLE_THREAD=0 remains only for comparison with previous threading. This document supersedes earlier diagnostic guides' default-setting descriptions.

08 performs one warm-up plus ten measured runs in the same TIDL session. Every run checks output shape, finite values, absolute CPU-reference error, and a valid TIDL processing interval. It also records maximum change from the first output. Output drift is reported without inventing a separate pass threshold. The CPU reference is one execution of the same input.

Final success in05 means **functional validation passed**. Direct MMA evidence, application-level accuracy, and long-duration stability remain separate. This avoids confusing the previous exit 2 policy with functional failure.

Local C++/shell syntax checks and package checksums are ready. ARM64 linking/repeated board execution remain Unverified at this stage. The 120-second limit covers warm-up and all repeats. On timeout, inspect logs rather than arbitrarily increasing counts or extending the limit.

## 1. User upload and backup

From the host project root:

```bash
scp bbai64-porting/rpmsg-work/repeat-validation.tar.gz beagle:~/
```

On the board:

```bash
cd ~/bbai64-porting
test ! -e before-repeat-validation.tar && \
 tar -cf before-repeat-validation.tar src/ort-probe.cpp scripts/05-check-onnx-ep.sh scripts/06-diagnose-tidl-run.sh
```

Proceed only after a successful backup:

```bash
tar -xzf ~/repeat-validation.tar.gz -C ~/bbai64-porting
cd ~/bbai64-porting
sha256sum -c staging/manifests/repeat-SHA256SUMS
```

Keep kernel, noeth firmware, model, and diagnostic-lib. Neither reboot nor strace is needed.

## 2. Repeated test

```bash
cd ~/bbai64-porting
sudo env RPMSG_LIB_DIR="$PWD/rpmsg-work/diagnostic-lib" \
 bash scripts/08-check-tidl-repeat.sh \
 "$HOME/models/resnet18/model.onnx" "$HOME/models/resnet18/artifacts/" \
 "$HOME/models/resnet18/input.f32" 1.0
```

Expect functional success and probe exit 0. Check ITERATION index=0(warmup), index=1..10, and REPEAT_OK warmup=1 measured=10. Each run must have CPU error≤1.0 and a valid TIDL interval.1.0 is a connectivity-test tolerance, not an overall model-accuracy acceptance criterion.

REPEAT_OK mean/min/max are host target.Run elapsed times excluding warm-up. They include debug output, CPU copies, and scheduling; do not call them pure MMA latency or production performance. Layer cycles/subgraph timings are different measurements and must not be combined without checking units.

On failure, analyze the detailed log and before/after C71x logs. Preserve evidence before repeating commands or rebooting. A pass does not validate long-duration, multiple-input, or reboot-repeat behavior.

## 3. Package results and restore

```bash
# Replace with the actual result directory name.
sudo tar -czf "$HOME/tidl-repeat-result.tar.gz" \
 -C "$HOME/bbai64-porting/tidl-results" run-diag.ACTUAL_NAME
```

Restore:

```bash
cd ~/bbai64-porting
tar -xf before-repeat-validation.tar
```

Do not invoke the new08 script after restoration. No reboot is needed because board configuration, kernel, and firmware are unchanged.

## Levels of acceleration evidence

- **Functional execution Verified:** single-run fddW6r demonstrated Run, output comparison, TIDL benchmark, and layer cycles.
- **Strong C71x-path evidence:** the same execution includes remote graph creation, C7x heap handling, TIDL layer cycles, and output return—not merely service presence.
- **Direct MMA verification incomplete:** explicit correspondence to MMA-specific instructions/hardware counters or target profiles remains necessary. Do not claim the current numbers alone provide direct proof.

Once repeats pass, pin settings in the installation guide and correlate the SDK profiler's MMA metrics with returned data and source. If no explicit metric exists, leave it Unverified and separate from accuracy/stability evaluation. No board upload or inference was performed during preparation.
