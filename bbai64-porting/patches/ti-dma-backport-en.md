# Scope of the TI DMA Backport to r47

The TI Linux 6.12 SDK kernel release fragment15b58b1dcd0e resolves to public commit 15b58b1dcd0e0a79d83740b81da1a1367f6f3f68, containing both the exporter and remoteproc attach ioctl. Target BeagleBoard6.18.39-arm64-k3-r47 is commit c03783811916b255c974912b3fd2eceb30fa8146. [TI baseline](https://github.com/TexasInstruments/ti-linux-kernel/commit/15b58b1dcd0e0a79d83740b81da1a1367f6f3f68) · [r47 baseline](https://github.com/RobertCNelson/linux-stable-rcn-ee/commit/c03783811916b255c974912b3fd2eceb30fa8146)

## Patch1: register reserved-memory DMA heaps

- Candidate code is TI drivers/dma-buf/heaps/carveout-heap.c: early reservation registration, page-alignment checks, gen_pool, DMA-BUF exporting, and cache synchronization. Add DMABUF_HEAPS_CARVEOUT to Kconfig/Makefile and enable it. Initially build it in as TI does, retaining OF_RESERVED_MEM/HAS_IOMEM/GENERIC_ALLOCATOR dependencies. r47 headers contain the early reserved-memory macro and fdt_node; early-DT access timing and DMA API compatibility still need build/boot verification. [TI implementation/build settings](https://github.com/TexasInstruments/ti-linux-kernel/tree/15b58b1dcd0e0a79d83740b81da1a1367f6f3f68/drivers/dma-buf/heaps)
- The current dma-heap-carveout node must register carveout_vision_apps_shared-memories. Preserve its512MiB reservation/cache attributes. First require sysfs and /dev presence plus successful4KiB allocation/mapping/SYNC.

## Patch2: SDK address-query ABI

- Candidate changes cover include/uapi/linux/remoteproc_cdev.h, drivers/remoteproc/remoteproc_cdev.c, remoteproc_core.c, declarations, and DMA-BUF dependencies. Beyond ioctl dispatch, track per-file references, attach/map, contiguous ranges, and unmap/detach/put on close. Direct TI code also changes shutdown-on-release scope; preserve r47 behavior. [TI character device](https://github.com/TexasInstruments/ti-linux-kernel/blob/15b58b1dcd0e0a79d83740b81da1a1367f6f3f68/drivers/remoteproc/remoteproc_cdev.c) · [TI attachment implementation](https://github.com/TexasInstruments/ti-linux-kernel/blob/15b58b1dcd0e0a79d83740b81da1a1367f6f3f68/drivers/remoteproc/remoteproc_core.c)
- SDK/TI UAPI both use _IOWR(0xB7,0,...) and a32-bit fd/64-bit address structure. Check address offset8 and total size 16 on AArch64. SDK names the field phys; TI calls it da. TI actually returns **sg_dma_address()** mapped to the remoteproc device; do not assume CPU physical-address equality. SDK /dev/remoteproc0 currently identifies C66 DSP0. Check that its DMA mapping matches the SDK shared region and addresses consumed by C71x. [TI UAPI](https://github.com/TexasInstruments/ti-linux-kernel/blob/15b58b1dcd0e0a79d83740b81da1a1367f6f3f68/include/uapi/linux/remoteproc_cdev.h) · [SDK UAPI](../src/dma_buf_phys.h:33)
- Original TI code retains a reference until close if copy_to_user fails after list insertion. Clean it up immediately in the backport; review concurrent requests/core cleanup and list/reference lifetimes. Include allocation failures and mapping release in review. Preserve existing access restrictions.

## Implementation and validation order

1. Apply independently in a separate r47 tree and build relevant ARM64 objects with the board configuration. Check DMA-BUF namespace/dependencies and userspace ABI size.
2. Validate the exporter on a recoverable SD first. With both patches booted, use03 --allocate to check SDK device numbering, [0xb8000000,0xd8000000) addresses, and cache synchronization. Defer04 on identification/range failure.
3. Check TIOVX initialization/peer communication in04 and single-model output plus C71x/MMA offloading in05.

This is the initial scope analysis. The implemented patch tracks mappings per character-device fd instead of porting all remoteproc-core code. See the [patch guide](README-en.md) for actual changes and build records.
