# Choosing Components and Planning a TIDL Port

This guide helps the engineer decide **which components to reuse, which features to enable, and which layer to modify first**. Use the [reproduction essentials](01-reproduction-en.md) for commands and the [troubleshooting record](02-troubleshooting-en.md) for decision history. The baseline is the TI ONNX Runtime TIDL EP path on J721E; other SoCs and releases require a fresh component/support assessment.

## 1. Components in the inference path

The flow is **host model compilation → A72 application/ORT → TIDL EP and TIDL-RT → TIOVX/IPC and shared memory → C71x TIDL firmware and MMALIB/MMA → returned output**. A port must prepare both the Linux application environment and remote-core firmware.

| Component | Responsibility | Porting decision or preparation |
|---|---|---|
| x86 host TIDL Tools | Compile ONNX into SoC-specific network/I/O artifacts and calibrate quantization | Select the SoC/release matching the target runtime; the full compilation environment need not be installed on the board |
| A72 application, TI ORT, TIDL EP | Load models, prepare tensors, delegate supported operations, handle CPU execution and outputs | This project uses TI ORT 1.15.0 C++; other frontends need separate compatibility validation |
| TIDL-RT, TIOVX, Vision Apps, app_utils | Create OpenVX graphs/remote targets and manage buffers, IPC, initialization | Required dependencies of the SDK binary path used here; distinguish these from installing all demos |
| C71x RTOS firmware, TIDL, MMALIB | Register the TIDL target and execute remote inference/optimized kernels | Use a matching SDK image or rebuild a coherent variant; validate MMA use separately through profiling |
| MAIN R5F and C66x peers | Participate in the shipped Vision Apps startup synchronization/services | C71x computes this model, but removing peers also requires changing peer lists and synchronization |
| Linux K3 remoteproc, RPMsg, TI SCI/mailbox | Start/control remote cores, exchange messages, connect power/resource management | Check implementation and actual responses in the board kernel |
| DT/firmware memory maps, DMA-BUF/heaps | Provide load regions and shared IPC/descriptors/tensors | Align address, lifetime, and cache contracts across both sides |
| Bootloader, SYSFW, board support | Establish Linux/core boot and resource assignments | Preserve the board chain first; revisit only when a conflict is established |

See [runtime dependency analysis](../docs/tidl-ep-porting-readiness-en.md) for DSO and startup-peer evidence.

## 2. Feature decisions and the recommended starting point

Start with **one file-input ONNX classifier, minimal user space, and the shipped peer configuration**. Add required I/O and board services after establishing inference, so failures remain attributable.

| Decision | Consequences | Choice in this project |
|---|---|---|
| File inference or camera/display pipeline | Files need tensor preprocessing; camera/display also need CSI/ISP, sensors, DSS, buffer paths and ownership | File input first; camera/display operation is outside the validated scope |
| ETHFW services | Virtual Ethernet ports, remote configuration, and related gPTP/TSN functions require board Ethernet/PHY/resource integration | Disabled after MCU2_0 stalled in EVM ETHFW initialization; Linux eth0/SSH retained. [Impact](../bbai64-porting/docs/ethfw-role-and-disable-en.md) |
| Shipped multicore or C71x-focused minimum | Reducing cores changes host/RTOS peers, startup barriers, and shared-region initialization ownership | Retain C71x, two C66x, two MAIN R5F; preserve existing MCU R5F services |
| SDK binary reuse or source rebuild | Reuse minimizes changes; rebuild only components with demonstrated ABI/allocator/board-initialization differences | Reuse TI runtime, rebuild MCU2_0 noeth, use a compatible RPMsg library |
| Existing Linux or TI reference kernel | Existing Linux needs missing TI interfaces ported; reference kernel still needs board DT/boot validation | Retain Debian/r47 with four kernel patches |
| C++ or Python application | Python additionally requires a matching ORT binding/Python ABI | Validate C++ first to remove binding differences |
| Full offload or partial CPU execution | Operator support/EP partitioning determine placement; acceptable fallback depends on accuracy/latency goals | ResNet18 delegates 49/49 nodes; do not assume this for another model |

Disabling ETHFW is different from BUILD_MCU_BOARD_DEPENDENCIES=no, which also changes other EVM camera/display dependencies. Choose required features first. **Reusing shipped firmware does not imply support for every board feature.**

## 3. Porting order and expected outputs

| Order | Work | Deliverable or gate |
|---|---|---|
| 1. Select functionality/release | Choose SoC, model/frontend, I/O, ETHFW/peers, Debian constraints; pin corresponding SDK set | Architecture, feature decisions, version inventory |
| 2. Identify Linux/RTOS differences | Compare actual boot/DT/kernel source/config, firmware maps, DSO requirements and SDK interfaces | Required DT changes, missing drivers/UAPI, rebuild list |
| 3. Prepare memory/kernel | Integrate core/shared regions; enable existing functionality or minimally backport missing code | Coherent DT/patches/image/modules candidate and recovery entry |
| 4. Prepare/start board firmware | Preserve map/peers; explicitly omit unnecessary EVM services | IPC services and RTOS synchronization, not just running cores |
| 5. Validate shared memory/host init | Check heap/address/sync and RPMsg return addresses, then isolated runtime | Step03 host DMA and Step04 initialization pass |
| 6. Model/inference | Validate matching compiled artifacts on CPU/host TIDL, then board EP | Actual graph verify/Run/output return, CPU comparison, processing intervals |
| 7. Pin the working set | Repeats, profiling, hashes, installation/recovery | Reproducible functional setup; separate accuracy/performance/endurance plans |

Host model validation can proceed independently alongside stages2–5. Board inference follows kernel/firmware/shared-memory preparation. The historical C++ reproduction uses explicit thread settings. For Python on the same ported BBAI64, the official TI TIDL Tools `11_02_04_00` wrapper passed with TI ORT 1.15.0 and the SDK's isolated Python 3.12 environment. Use its built-in intra-op setting. Direct Python sessions with all thread settings left at their defaults also passed for this ResNet18 input. On another configuration, check the Python ABI, TIDL EP availability, and actual offload with a positive TIDL processing interval and a CPU output comparison. [Python guide](../bbai64-porting/python-ort-validation/README-en.md), [board results](../bbai64-porting/python-ort-validation/results-en.md)

## 4. How to backport kernel and driver functionality

### Decide whether to enable existing code or port an implementation

Obtain source/configuration matching the running kernel and compare the devices, ioctls, and sysfs attributes actually used by SDK user space. If functionality exists, fix Kconfig/module/DT connections first. Only port from the matching TI kernel when implementation is absent. A kernel version or device node alone does not establish support.

### Minimal changes needed here

| Change | Purpose | Boundaries to review |
|---|---|---|
| 0001: TI carveout heap exporter | Allocate shared buffers from fixed reserved memory | DT compatible/early registration, DMA-BUF API, cache synchronization, allocation-failure cleanup |
| 0002: remoteproc DMA-BUF address ioctl | Return addresses used for DSP-shared buffers | UAPI size/alignment, privileges, attach/map/unmap, fd lifetime, contiguity |
| 0003: K3 DMA parent mapping | Avoid mapping through a remoteproc class device without DMA configuration | DMA mask, IOMMU, platform parent, DMA versus physical addresses |
| 0004: actual local RPMsg address | Supply the allocated reply port instead of ANY request -1 | Endpoint open/release locking, sysfs semantics, preserved dynamic allocation/collision handling |

These four patches target r47; do not assume every release needs all of them. [Patches and rationale](../bbai64-porting/patches/README-en.md), [DMA analysis](../bbai64-porting/patches/ti-dma-backport-en.md).

### Implementation workflow

1. **Separate contracts:** keep exporter, address-query, and RPMsg changes in separate patches, including relevant headers/Kconfig/Makefile.
2. **Adapt to destination APIs:** review DMA-BUF APIs/namespaces, device lifetime, error cleanup, locking, access control rather than copying TI files verbatim. State whether user-space ABI stays compatible or changes with the port.
3. **Preserve unrelated behavior:** retain remoteproc shutdown semantics/MCU services. Do not substitute constant addresses or remove security checks merely to pass a test.
4. **Check and build:** validate sequential application, diffs, UAPI layout, memory ranges and relevant objects, then have the user build a separately named full image with matching modules.
5. **Test by boundary:** use a recoverable entry; check heap/ioctl/actual RPMsg addresses, then TIOVX, then inference. Do not alter an already passing boundary without evidence.

If kernel buffer/address contracts cannot support the binary, porting the allocator/runtime is an alternative. RTOS linker/MMU changes cannot be solved by Linux driver patches alone; validate DT and firmware together. Preserve the division of work: local source/patch preparation, with kernel building/deployment and all board application performed by the user.

## 5. Additional checks

Apply these detailed checks after deciding the configuration and implementation direction.

### 5.1. Pin the complete version set

Record TIDL Tools/model importer, ARM runtime/EP/ORT, C71x TIDL/MMALIB, Vision Apps/TIOVX/app_utils, RTOS/PDK/SYSFW, and Linux UAPI independently. A shared 11.02 release label does not make components interchangeable. Use tags, commits, binary hashes, SONAMEs, required symbols, and actual loader paths as evidence. The official J721E 11.02 RTOS documentation specifies Linux 11.02.00.04/TIDL11_02_04_00/MMALIB 11_02_00_06. [Official components](https://software-dl.ti.com/jacinto7/esd/processor-sdk-rtos-jacinto7/11_02_00_06/exports/docs/psdk_rtos/docs/user_guide/sdk_components_j721e.html)

### 5.2. Board, boot, and memory contracts

- Identify the SoC, GP/HS security variant, signing requirements, boot medium, actual extlinux entry, and firmware embedded in initrd.
- Preserve board DTS includes/overlays. Compare reserved-memory with ELF LOAD segments, resource tables, trace, vrings, and shared descriptors.
- Check memory-region order and phandles against the actual kernel driver. Do not infer C66 DMA-pool ownership from node names alone.
- Check assumptions equating DMA and physical addresses, IOMMU use, contiguity, address width, cache synchronization, and CMA/dedicated heaps. Renaming a generic heap is not a compatibility fix.
- Partial Sciclient success does not establish full compatibility of SYSFW resource assignments, IRQ/UDMA, and MMA-related configuration.

### 5.3. Host, kernel, and RTOS boundaries

Validate both kernel configuration and actual behavior. Before applying this project's TI ioctl/exporter patches to another kernel, review ABI, device lifetime, DMA parent, and access restrictions. Distinguish RPMsg ANY requests from actual allocated addresses. Preserve kernel allocation and report the correct address rather than substituting a constant. Isolate SDK and distribution ORT versions. A newer Debian GLIBC alone does not prove complete ABI compatibility.

EVM firmware may depend on GESI/QENET, DSS/I2C, and pinmux configuration. Disabling ETHFW is a choice for this BBAI64 setup, not a universal porting requirement. Ethernet virtual ports and gPTP/TSN features need appropriate board support. R5F/C71x trace and general shared logs are different facilities; account for cache visibility and historical messages.

### 5.4. Model and quantization contracts

Pin the SoC and Tools, and hash the model, artifacts, input, and preprocessing as one set. Check RGB/BGR, NCHW/NHWC, shape/dtype, mean/scale, and byte order. Successful CPU/host TIDL execution reduces the likelihood of preprocessing/file errors but does not rule out C71x code-generation or resource problems. calibration2/iterations5 and top1 agreement on one image are not application-level accuracy validation. Choose representative calibration/evaluation data and acceptable accuracy loss for the intended use.

### 5.5. Success levels and stop conditions

1. Distinguish device enumeration, initialization, actual graph verification/remote creation, and Run/output return.
2. Check CPU-reference error, finite values, shapes, repeated-output drift, and benchmark intervals for each invocation.
3. Separate evidence of C71x execution from direct MMA profiling. Layer cycles alone do not directly prove execution of a particular MMA instruction.
4. Do not equate debug-enabled host Run latency with accelerator-only time or production performance.
5. Narrow timeouts using the last marker, stacks, or system calls; do not extend timeouts or recompile without evidence.

Label conclusions **Verified/Likely/Unverified**. Continue when a fixable boundary has been identified; proceed conditionally when required source, tools, and recovery are available; defer when those prerequisites cannot be obtained. A conclusion that Debian cannot be retained must identify the specific blocking interface.

## 6. Contents of summary/files

Included: four kernel patches and build configuration/scripts; noeth rebuild patches/tools; baseline/candidate DTs and map; validation scripts and ORT headers/probe source; the small RPMsg0.6.11 diagnostic library; SDK source-path/hash manifests and a selective exporter. Use of libraries remains subject to the original TI SDK license. The RPMsg diagnostic patch and TI license are included in files/rpmsg-work.

Excluded: full Linux/SDK source, kernel images/full module trees, large SDK runtime binaries, RTOS ELFs, models/artifacts, Docker images, and historical trace collections. Generate or select these from the original project and pinned SDK. These large files are still required; summary simply avoids storing duplicate copies. The three notes index the original project, which must also be retained to use all supporting links.
