# Unresolved Items Before Deployment

1. **Kernel source and TI extensions.** The board reports source package linux-upstream1trixie; the exact vendor commit is Unverified at this stage. Start from the [BeagleBoard build/patch repository](https://github.com/beagleboard/arm64-mainline-linux). Public-tag inspection did not establish the exact tree, and local Git lookup failed with DNS errors. On a host with access, identify source-package originals and matching patches/commit:
   ```bash
   dpkg-query -W -f='${source:Package} ${source:Version}\n' linux-image-6.18.39-arm64-k3-r47
   apt-cache showsrc linux-upstream
   git ls-remote --tags https://github.com/beagleboard/arm64-mainline-linux.git '*6.18.39*'
   # On a separate build host configured with matching vendor deb-src entries
   apt-get source linux-upstream=1trixie
   ```
   Package name/version alone does not prove tree identity. Compare patches, release strings, supplied configuration, and commits.
2. **Heap and ioctl.** Only system/default_cma_region/reserved were observed. CONFIG_REMOTEPROC_CDEV=y and an ioctl symbol do not prove TI-command handling. Compare the current kernel against SDK 6.12.57-ti:
   ```bash
   git -C "$KERNEL_SOURCE" grep -nE 'dma-heap-carveout|RPROC_IOC_DMA_BUF_ATTACH|dma_buf_phys_data|rproc_device_ioctl'
   ```
   Review drivers/dma-buf/heaps/ exporter/Kconfig, remoteproc_cdev.c dispatch, UAPI, and pin/map/release paths. The SDK contract is in app_utils/utils/mem/src/app_mem_linux_dma_heap.c and include/linux/dma_buf_phys.h. Port only confirmed missing interfaces; validate DMA masks, contiguity, physical versus device addresses, lifetimes, and access controls. Standard CMA alone is insufficient. No applicable patch/build was included at this initial stage.
3. **DT/firmware.** The candidate had not booted. Check GP/HS/signing, UART/original-SD recovery, TI SCI resources, and MAIN R5F0_0 ETHFW dependencies. R5F DA0 TCM and high heap are separate from DDR checks. Stop if kernel/firmware interpret reservations differently.
4. **Validation scope.** The DMA probe tests host allocation/mmap/SYNC/TI address return. RPMsg enumeration does not establish DSP round trips or cache coherence. These require a compatible firmware protocol or actual TIOVX input/output and firmware traces. MMA evidence needs separate firmware execution/profiling records.
5. **Model and licensing.** Compiled test artifacts had not been generated. Follow the pinned host procedure in the deployment guide. Review SDK manifests/licenses before sharing binaries/headers with third parties.

**Current test scope:** candidate-DT boot and core start can be checked without source access. If the applied DT still yields no heap or failed allocation/address ioctl, defer SDK runtime work. Decide from device/function tests rather than source availability alone. [Validation order](deployment-guide-en.md)
