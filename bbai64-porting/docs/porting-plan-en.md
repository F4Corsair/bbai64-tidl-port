# BBAI64 TIDL EP Porting Plan

**Review package; not yet validated on hardware at this stage.** Baseline: Debian 13.6 / 6.18.39-arm64-k3-r47 and the BBAI64 boot chain. Pin SDK RTOS 11.02.00.06 / Linux 11.02.00.04 / Tools 11_02_04_00 / TI ORT 1.15.0. [TI version table](https://github.com/TexasInstruments/edgeai-tidl-tools/tree/11_02_04_00#version-compatibility)

- [Manual deployment and validation](deployment-guide-en.md), [unresolved items](unresolved-issues-en.md), [results template](validation-results-template-en.md).
- [Origins, paths, hashes, links, SONAMEs, and NEEDED entries](../staging/manifests/components.tsv), [firmware mapping](../staging/manifests/firmware-map.tsv), [static validation log](offline-validation.log).
- `staging/dt/` contains a candidate derived from the collected board boot DTB and TI reference material. Regenerate with `scripts/prepare-dt.py`. The EVM DTBO is a reference for address and policy comparison.
- `staging/firmware/` contains C71x, two C66x, and two MAIN R5F images, including signed variants. Preserve the existing MCU R5F. The MAIN R5F1 pair follows the SDK map to avoid conflicting references; no firmware is deployed to that pair.
- `staging/lib/` isolates TI ORT/providers, TIDL-RT, Vision Apps (including TIOVX), and rpmsg-char. EGL/GLES/GBM and C/C++ runtimes use Debian-provided SONAMEs.
- Test baseline, candidate DT/kernel contracts, cores, RPMsg/DMA, TIOVX, and finally ONNX outputs/offloading evidence. Kernel patches, model compilation, and on-board acceleration validation remain pending at this stage.

Static checks found DDR ELF segments and resource tables within their carveouts and no overlap among 26 active reserved regions. Observed CMA and OP-TEE areas were included. Peripheral/MCU node properties and the FDT reservation table were preserved. C71x high heap, R5F TCM translation, kernel security policy, and ETHFW resources still require hardware checks. The candidate DTB was generated with Python FDT tooling; neither a DTC build nor board boot was performed.

## Proceeding without UART or TI Git access

A full backup may be omitted immediately after flashing if there is no data to preserve. First establish that another PC can repair or reflash the SD if SSH is lost. A unique cmdline marker in the test entry plus live-DT validation identifies the applied configuration after reboot over SSH.

Obtaining kernel source is no longer a prerequisite for boot and remoteproc inspection. Test the DT alone before adding firmware, then inspect cores and RPMsg. DMA heap and address-query behavior are separate functional gates for inference. [Manual deployment guide](deployment-guide-en.md)
