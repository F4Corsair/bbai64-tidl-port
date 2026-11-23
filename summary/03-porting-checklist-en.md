# TIDL Porting Checklist for Other Releases and Boards

## 1. Pin the complete version set

Record TIDL Tools/model importer, ARM runtime/EP/ORT, C71x TIDL/MMALIB, Vision Apps/TIOVX/app_utils, RTOS/PDK/SYSFW, and Linux UAPI independently. A shared 11.02 release label does not make components interchangeable. Use tags, commits, binary hashes, SONAMEs, required symbols, and actual loader paths as evidence. The official J721E 11.02 RTOS documentation specifies Linux 11.02.00.04/TIDL11_02_04_00/MMALIB 11_02_00_06. [Official components](https://software-dl.ti.com/jacinto7/esd/processor-sdk-rtos-jacinto7/11_02_00_06/exports/docs/psdk_rtos/docs/user_guide/sdk_components_j721e.html)

## 2. Board, boot, and memory contracts

- Identify the SoC, GP/HS security variant, signing requirements, boot medium, actual extlinux entry, and firmware embedded in initrd.
- Preserve board DTS includes/overlays. Compare reserved-memory with ELF LOAD segments, resource tables, trace, vrings, and shared descriptors.
- Check memory-region order and phandles against the actual kernel driver. Do not infer C66 DMA-pool ownership from node names alone.
- Check assumptions equating DMA and physical addresses, IOMMU use, contiguity, address width, cache synchronization, and CMA/dedicated heaps. Renaming a generic heap is not a compatibility fix.
- Partial Sciclient success does not establish full compatibility of SYSFW resource assignments, IRQ/UDMA, and MMA-related configuration.

## 3. Host, kernel, and RTOS boundaries

Validate both kernel configuration and actual behavior. Before applying this project's TI ioctl/exporter patches to another kernel, review ABI, device lifetime, DMA parent, and access restrictions. Distinguish RPMsg ANY requests from actual allocated addresses. Preserve kernel allocation and report the correct address rather than substituting a constant. Isolate SDK and distribution ORT versions. A newer Debian GLIBC alone does not prove complete ABI compatibility.

EVM firmware may depend on GESI/QENET, DSS/I2C, and pinmux configuration. Disabling ETHFW is a choice for this BBAI64 setup, not a universal porting requirement. Ethernet virtual ports and gPTP/TSN features need appropriate board support. R5F/C71x trace and general shared logs are different facilities; account for cache visibility and historical messages.

## 4. Model and quantization contracts

Pin the SoC and Tools, and hash the model, artifacts, input, and preprocessing as one set. Check RGB/BGR, NCHW/NHWC, shape/dtype, mean/scale, and byte order. Successful CPU/host TIDL execution reduces the likelihood of preprocessing/file errors but does not rule out C71x code-generation or resource problems. calibration2/iterations5 and top1 agreement on one image are not application-level accuracy validation. Choose representative calibration/evaluation data and acceptable accuracy loss for the intended use.

## 5. Success levels and stop conditions

1. Distinguish device enumeration, initialization, actual graph verification/remote creation, and Run/output return.
2. Check CPU-reference error, finite values, shapes, repeated-output drift, and benchmark intervals for each invocation.
3. Separate evidence of C71x execution from direct MMA profiling. Layer cycles alone do not directly prove execution of a particular MMA instruction.
4. Do not equate debug-enabled host Run latency with accelerator-only time or production performance.
5. Narrow timeouts using the last marker, stacks, or system calls; do not extend timeouts or recompile without evidence.

Label conclusions **Verified/Likely/Unverified**. Continue when a fixable boundary has been identified; proceed conditionally when required source, tools, and recovery are available; defer when those prerequisites cannot be obtained. A conclusion that Debian cannot be retained must identify the specific blocking interface.

## Contents of summary/files

Included: four kernel patches and build configuration/scripts; noeth rebuild patches/tools; baseline/candidate DTs and map; validation scripts and ORT headers/probe source; the small RPMsg0.6.11 diagnostic library; SDK source-path/hash manifests and a selective exporter. Use of libraries remains subject to the original TI SDK license. The RPMsg diagnostic patch and TI license are included in files/rpmsg-work.

Excluded: full Linux/SDK source, kernel images/full module trees, large SDK runtime binaries, RTOS ELFs, models/artifacts, Docker images, and historical trace collections. Generate or select these from the original project and pinned SDK. These large files are still required; summary simply avoids storing duplicate copies. The three notes index the original project, which must also be retained to use all supporting links.
