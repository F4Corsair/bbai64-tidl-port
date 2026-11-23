# Board Validation Results

- Test time / boot medium / UART log:
- `uname -a` / baseline and candidate DTB SHA256 / GP or HS determination:
- Firmware set / kernel source and change identifiers:
- ONNX / artifacts / input SHA256, absolute tolerance:

| Stage | Status | Result and evidence |
|---|---|---|
| 01 Baseline and live DT | Unverified | |
| 02 Cores, firmware, MCU attachment | Unverified | |
| 03 RPMsg, DMA, DSP data round trip | Unverified | |
| 04 Dynamic loading, TIOVX | Unverified | |
| 05 CPU comparison, delegation, C71x/MMA | Unverified | |

Attach Markdown summaries and detailed logs from `tidl-results/` plus UART/C71x profiles from the same execution. Script exit codes at this stage are success0, failure1, and unverified2. If only host DMA in03 or EP processing timing in05 has passed, state that scope and leave the remaining functions Unverified.
