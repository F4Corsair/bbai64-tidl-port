| English | 한국어 |
|---|---|
| [English README](README.md) | [한국어 README](README-ko.md) |

# BBAI64 TIDL Porting Record

Implementation notes and reproduction resources for running inference through the TI ONNX Runtime TIDL Execution Provider on BeagleBone AI-64 (J721E), while retaining Debian.

**Verified results:** all 49 ResNet18 nodes assigned to TIDL; inference and CPU-output comparison passed; one warm-up and ten measured runs completed with no change in repeated outputs. Direct evidence of MMA use, application-level accuracy, and long-duration stability remain separate validation tasks.

## Start here

| Document | Contents |
|---|---|
| [Reproduction essentials](summary/01-reproduction-en.md) | Required steps, versions, commands, and remaining work starting from a stock system |
| [Troubleshooting record](summary/02-troubleshooting-en.md) | Problems encountered, fixes, and links to supporting documents |
| [TIDL porting checklist](summary/03-porting-checklist-en.md) | Compatibility and validation checks for other releases and boards |

Required patches, configuration files, and scripts are in [summary/files](summary/files). Full SDK and Linux source trees, large build outputs, and models are excluded. The shortened procedure has not yet been rerun end to end on a freshly flashed SD card; check its prerequisites and stop conditions.

## Validated configuration

| Item | Version or setting |
|---|---|
| Board | BeagleBone AI-64 / TI J721E |
| OS | Debian 13.6 |
| Kernel | Based on 6.18.39-arm64-k3-r47, with compatibility patches; tidl3 build |
| PSDK | RTOS 11.02.00.06 / corresponding Linux 11.02.00.04 |
| TIDL Tools / TI ONNX Runtime | 11_02_04_00 / 1.15.0 |
| MCU2_0 firmware | ETHFW disabled |
| ORT execution | Single-threaded, sequential execution, spinning disabled |

## Supporting evidence

- [Porting feasibility, quantization reassessment, and repeated-run results](bbai64-porting/docs/porting-reassessment-en.md)
- [IPC, RPMsg, and TIDL execution failure analysis](bbai64-porting/docs/rpmsg-failure-analysis-en.md)
- [ETHFW responsibilities and the impact of disabling it](bbai64-porting/docs/ethfw-role-and-disable-en.md)
- [Initial SDK and Device Tree analysis](docs/psdk-porting-preanalysis-en.md)

Detailed documents include historical states and intermediate procedures. Use the latest reproduction essentials when reproducing the setup; do not repeat superseded failure stages.

## Working rules

Keep the original SDK read-only. The user builds and deploys kernels and performs board uploads, installation, and reboots. Apply changes incrementally while preserving a working boot configuration and an SD-card recovery path.

This repository primarily tracks the README files, all of summary, and Markdown documents referenced from summary. Links to excluded binaries and logs may require the original workspace.
