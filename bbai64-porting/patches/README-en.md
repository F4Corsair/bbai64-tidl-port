# Vision Apps Kernel Patches for BeagleBoard r47

Target: 6.18.39-arm64-k3-r47, commit c03783811916b255c974912b3fd2eceb30fa8146. Apply the two initial patches in order. [TI source and backport analysis](ti-dma-backport-en.md)

1. [0001: carveout heap](0001-dma-buf-add-TI-reserved-memory-carveout-heap.patch) ports the TI exporter, adding allocation-failure cleanup and initialization of returned buffers.
2. [0002: remoteproc address lookup](0002-remoteproc-support-scoped-TI-Vision-Apps-DMA-BUF-add.patch) supports the SDK ioctl ABI. It accepts only privileged callers' Vision Apps heap buffers, returning an address only for contiguous mappings where DMA and physical addresses match. Mapping references are per fd and released on close. Existing automatic-shutdown settings are preserved.

Use a separate r47 worktree. Set PATCH_DIR to this directory and BOARD_CONFIG to the absolute path of the collected kernel.config.

```bash
git apply --check "$PATCH_DIR"/0001-*.patch
git apply "$PATCH_DIR"/0001-*.patch
git apply --check "$PATCH_DIR"/0002-*.patch
git apply "$PATCH_DIR"/0002-*.patch

export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
mkdir -p out
scripts/kconfig/merge_config.sh -m -O out "$BOARD_CONFIG" "$PATCH_DIR/vision-apps-r47.config"
make O=out olddefconfig
make O=out -j"$(nproc)" drivers/dma-buf/heaps/carveout-heap.o drivers/remoteproc/remoteproc_cdev.o
```

Sequential clean application, ARM64 object compilation, and ioctl number/structure-size/field-offset equivalence were checked. [Validation record](arm64-build-validation.log)

Next, boot a separate test-kernel release on a recoverable SD. Keep image/modules as one matching set. After preserving a working boot path, check heap registration,03 --allocate, then TIOVX initialization. On ERANGE, inspect DSP0 DMA mapping against the shared region. Actual boot/DMA behavior requires hardware validation.

The complete 6.18.39-arm64-k3-r47-tidl1 image/modules and package validation were subsequently completed. See the [board guide](../docs/r47-kernel-deployment-en.md) for installation/recovery.

Patch0003 was added for03's DMA-mapping failure. The [tidl2 build guide](tidl2-build-start-en.md) records sequential checks and build commands.

## 0004: report the actual local RPMsg endpoint (tidl3 candidate)

Fix sysfs src retaining the requested -1 after automatic allocation. src_show returns the open endpoint address under ept_lock. Applied locally on top of0001–0003, with out-tidl3 configuration prepared. **Kernel build was not performed at that stage.** [User build guide](tidl3-build-start-en.md). Keep noeth firmware; no full OS rebuild is needed.
