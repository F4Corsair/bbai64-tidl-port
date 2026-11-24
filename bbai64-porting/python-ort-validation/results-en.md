# TI Python ONNX Runtime Validation Results

## Confirmed

- The earlier C++ baseline on the board passed one warm-up and ten repeated inferences. Maximum absolute error relative to CPU output was 0.722227, with zero drift. [Earlier results](../docs/porting-reassessment-en.md)
- The board's default account has Python 3.13.5 with neither NumPy nor ORT installed in the system Python environment. The account lacks read and write access to the DMA heap and C71x RPMsg control devices.
- The SDK image includes AArch64 Python 3.12, NumPy, and TI Python ORT bindings. The official TI Python wrapper sets the intra-op thread count to 1. [Official source](https://github.com/TexasInstruments/edgeai-tidl-tools/blob/bb029fb79929e0fc0c2c13d2d40b13237eabbca1/runtimes/tidl_wrapper/python/onnxrt/onnxrt_wrapper.py#L196-L226)
- The board's default account verified the bundle hashes, imported NumPy 1.26.4 and TI ORT 1.15.0 under Python 3.12.12, and confirmed that `TIDLExecutionProvider` was available. The temporary directory was removed. [Board preflight log](board-import-preflight.log)

## Board results

In `results.DjdXAu`, imports succeeded and the TIDL EP was available. C71x reported `running` with firmware `j7-c71_0-fw`. The runner joined the two sysfs values with a newline and compared them with a single-line pattern, so it stopped before Case A. The recovered archive contains only `runner.log` and `environment.log`. The runner now writes both values on one line. [Board log](board-results.3iiZJLRM/runner.log)

In `results.LISG0J`, ResNet18 ran on Debian 13 with kernel `6.18.39-arm64-k3-r47-tidl3`, C71x firmware `j7-c71_0-fw`, Python 3.12.12, and TI ORT 1.15.0. The recovered files passed SHA256 checks, and the model and input hashes matched the prepared test files. [Run summary](board-results.yuaCA2OL/cases.tsv), [Environment and input hashes](board-results.yuaCA2OL/environment.log)

| Case | Exit code | Successful inferences | Maximum absolute error vs. CPU | Maximum absolute difference vs. A |
|---|---:|---:|---:|---:|
| A · Existing workaround | 0 | 11/11 | 0.7222270966 | 0 |
| B · Only `intra-op=1` specified | 0 | 11/11 | 0.7222270966 | 0 |
| C · ORT thread defaults | 0 | 11/11 | 0.7222270966 | 0 |
| Official TI Python wrapper | 0 | 11/11 | 0.7222270966 | 0 |

Each case completed the EP invocation and recorded a positive TIDL subgraph processing interval for the warm-up and all ten subsequent inferences. All four output arrays had zero run-to-run drift and identical SHA256 hashes. The maximum absolute error agrees with `0.722227` from the earlier board run at the reported precision. [A log](board-results.yuaCA2OL/A/probe.log), [B log](board-results.yuaCA2OL/B/probe.log), [C log](board-results.yuaCA2OL/C/probe.log), [Official wrapper log](board-results.yuaCA2OL/wrapper/probe.log)

**Conclusion.** The official TI Python wrapper works with this ported board configuration and ResNet18 input. Case B passed with the explicit inter-op, execution-mode, and spinning settings omitted. Case C also passed with all thread options omitted from the direct Python session. No further ablation was needed under the test plan. The historical C++ timeout and behavior with other models remain unverified.
