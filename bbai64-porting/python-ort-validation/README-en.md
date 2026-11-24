# BBAI64 TI Python ONNX Runtime Validation Guide

This test varies Python ONNX Runtime thread settings while reusing the existing ResNet18 model and TIDL artifacts. Case B tests the official TI wrapper's thread settings. If B passes, the runner also tests the wrapper itself from the same release. Case C is a reference run.

| Case | Settings |
|---|---|
| A | Intra-op and inter-op thread count set to 1, sequential execution, spinning disabled for both pools |
| B | Intra-op thread count set to 1, runtime defaults for the other thread settings |
| C | Runtime defaults for all thread settings |
| wrapper | Python wrapper from TI TIDL Tools 11_02_04_00 |

## Host preparation

Run from the project root. If you already have the bundle, skip `prepare.sh` and check its SHA256.

```bash
exp="$PWD/bbai64-porting/python-ort-validation"
bash "$exp/prepare.sh" "$exp/python-ort-bbai64.tar.gz"
sha256sum "$exp/python-ort-bbai64.tar.gz"
```

The bundle contains Python 3.12, its standard library, and packages extracted from the local SDK image, plus the TI wrapper pinned to the release commit. It runs without a system installation. The board's system Python is 3.13.5.

## Board execution and log collection

The board's default account lacks read and write access to the DMA heap and RPMsg control devices. Run the following commands using the existing `beagle` SSH alias.

```bash
remote_dir=$(ssh beagle 'mktemp -d /tmp/bbai64-python-ort.XXXXXXXX')
scp "$exp/python-ort-bbai64.tar.gz" "beagle:$remote_dir/"
ssh -t beagle "cd '$remote_dir' &&
    tar -xzf python-ort-bbai64.tar.gz &&
    bash run.sh \"\$HOME/models/resnet18\""
```

The runner checks bundle hashes, Python and ORT versions, and execution provider availability before using `sudo` to run each case in a separate process. Each process has a 120-second timeout and a five-second grace period before forced termination. If the model and artifacts are elsewhere, pass their directory as the first argument to `run.sh`. The test uses the existing kernel, device tree, firmware, deployed libraries, and model.

Set `result_name` to the actual `results.*` directory printed on the board. The commands create a new local directory for the recovered logs.

```bash
result_name=results.XXXXXXXX
local_run=$(mktemp -d "$exp/board-results.XXXXXXXX")
ssh beagle "cd '$remote_dir/$result_name' &&
    find . -type f -not -path '*/artifacts/*' -print0 |
    tar --null -T - -cf -" > "$local_run/results.tar"
tar -xf "$local_run/results.tar" -C "$local_run"
find "$local_run" -name '*.log' -o -name cases.tsv
(cd "$local_run" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
```

Check `cases.tsv` and any failed case logs locally, then remove the board's temporary directory for this session. Verify the value of `remote_dir` before running the cleanup command.

```bash
ssh -t beagle "case '$remote_dir' in /tmp/bbai64-python-ort.*) sudo rm -rf -- '$remote_dir';; *) exit 2;; esac"
```

If Python imports fail, preserve the board terminal output and any `runner.log`. Collect the logs before retrying after a device-access error, C71x state change, or failed baseline recheck.

## Interpreting results

- Each case runs one warm-up and ten further inferences in the same session. CPU and TIDL outputs must be finite and have the same shape and dtype. Maximum absolute error relative to the CPU output must be at most 1.0. Each call must have a positive TIDL subgraph processing interval.
- `cases.tsv` records the exit code, last Python stage, and counts of EP Invoke and graph log messages. The Invoke count includes entry and completion messages. See each `probe.log` for exact markers and errors. Record a stage with missing markers as unobserved.
- `comparison.log` records the maximum absolute difference between the first output from the current Case A and all 11 outputs of that case. The earlier board run reported a maximum absolute error of 0.722227 relative to CPU output and zero drift. Its raw arrays are unavailable, so the new Case A array is the direct comparison reference.
- An A failure stops the test. After B or C fails, the runner reruns A to check recovery. If A passes and B fails, the runner adds thread settings to B one at a time. It tests pairs if every single addition fails and reruns a passing candidate with the fewest explicit options. If B passes, it tests the official wrapper.
