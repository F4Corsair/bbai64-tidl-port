# Troubleshooting Record and Supporting Documents

For the working configuration, follow the [reproduction essentials](01-reproduction-en.md). Use this record if a previously encountered failure returns; these are not steps to reproduce.

| Stage | Observation → required change | Details |
|---|---|---|
| Release identification | Initial 11.02.00.07 assumption → confirmed RTOS .06/Linux .04/Tools 11_02_04_00 | [Initial analysis](../docs/psdk-porting-preanalysis-en.md), [reassessment](../bbai64-porting/docs/porting-reassessment-en.md) |
| DT/cores | Stock BBAI64 carveouts did not match SDK ELF addresses → integrate the SDK map into the board DT | [Strategy](../docs/bbai64-porting-strategy-en.md), [candidate map](files/staging/dt/sdk-memory-map.dtsi) |
| DMA heap | Vision Apps heap absent → kernel patch 0001 | [Backport rationale](../bbai64-porting/patches/ti-dma-backport-en.md) |
| DMA address | Missing ioctl/mapping failure → 0002+0003, using the K3 parent DMA device | [Earlier build guide](../bbai64-porting/patches/tidl2-build-start-en.md) |
| RTOS initialization | MCU2_0 running without endpoint 13; progress stopped inside ETHFW → noeth | [ETHFW responsibilities and limitations](../bbai64-porting/docs/ethfw-role-and-disable-en.md) |
| Diagnostic visibility | Truncated trace → R5F cache writeback | [Diagnostic variant](../bbai64-porting/firmware-work/deployment-trace-wb-en.md) |
| RPMsg address | Library returned0 for src=-1; TIDL session stalled → expose the actual address with kernel0004 | [tidl3 patch](files/patches/0004-rpmsg-char-report-bound-local-endpoint-address.patch), [full analysis](../bbai64-porting/docs/rpmsg-failure-analysis-en.md) |
| Model compilation | SIGBUS immediately after Docker tivxInit → shm_size=1gb | [Analysis](../tidl/sigbus-analysis-en.md), [Docker configuration](../tidl/compose.yaml) |
| TIDL Run | Graph verification passed but ORT Run stalled → threads1/sequential/spinning off for both sessions | [Threading diagnosis](../bbai64-porting/docs/ort-thread-diagnostics-en.md) |
| Repeated execution | One warm-up+10 runs passed; output drift 0 → preserve working settings | [Repeat guide](../bbai64-porting/docs/repeat-validation-en.md), [reassessment](../bbai64-porting/docs/porting-reassessment-en.md) |

`running`, `Initialization Done`, and RPMsg device presence do not prove inference success. The original 04 could incorrectly pass because SDK code overwrote an error status; the current script also checks error logs. The original 05 used Unverified/exit 2 for a functional pass with incomplete MMA evidence. The current version reports functional success separately from remaining validation.

Do not reintroduce solved failures after functional validation passes. Still unresolved are which of the four ORT settings directly prevents the stall, the exact internal ETHFW function that stopped, and direct MMA counters. Do not attribute the current inference behavior to historical DSS/Sciclient errors emitted at boot without further evidence.
