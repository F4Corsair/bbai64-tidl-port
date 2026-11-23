# tidl3 RPMsg Return-Address Compatibility Patch: User Build Guide

## Approach and preparation status

There is no need to recreate Debian or its rootfs. This change targets kernel rpmsg_char. Replacing a single module under the tidl2 name is not the default because active endpoints, module dependencies, and recovery can become confusing. **The user builds a new tidl3 image and matching modules**, preserving tidl2. Retain r47 and DMA patches0001–0003.

Prepared: patch 0004 applied to the independent kernel-work/linux tree; combined previous DMA changes checked; git diff --check passed; out-tidl3/.config prepared; host build/local-packaging scripts written. **No kernel compilation, linking, new binary generation, board upload, or application was performed at this stage.**

### Why fix kernel src reporting rather than reserve addresses in user space?

The actual endpoint is reserved at kernel open, but sysfs src_show exposes the request chinfo.src=-1. The library treats this as lookup failure and returns0. Choosing an arbitrary explicit address in user space complicates cleanup/retry after an open-time collision. Exposing the address already known to the kernel is smaller and preserves automatic allocation. User-space changes were initially considered; this approach was selected after reviewing open and failure cleanup.

Patch0004 reads an open endpoint's ept->addr under ept_lock; unopened devices retain chinfo.src. Pointer access uses the same lock as open/release/destroy. Request, allocation, and IPC wire formats are unchanged. The kernel still handles allocation collisions. ANY remains -1 before open; after open the actual address is returned.

Evidence: rpmsg_eptdev_open/release and src_show in drivers/rpmsg/rpmsg_char.c; __rpmsg_create_ept/idr_alloc in drivers/rpmsg/virtio_rpmsg_bus.c. Board UAPI compatibility and TIDL session success remain Unverified at this stage. This addresses a likely cause, not a guarantee of complete inference.

## 1. Host prerequisites

Start in bbai64-porting. Change only cd if the package was moved.

```bash
cd /home/corsair/Documents/sdk/ti_sdk_lab/bbai64-porting
# Run only if host tools are missing; installs packages with apt on the host.
bash scripts/install-kernel-build-deps.sh
```

Skip reinstalling tools if the tidl2 build environment remains. Requirements include make, ARM64 GCC/binutils, flex, bison, OpenSSL/ELF development headers, and kmod/depmod.

## 2. Check preparation

In this workspace, preparation has already created out-tidl3/.config. **Do not rerun it here.** On another PC with the r47/0001–0003 source, run:

```bash
bash scripts/prepare-tidl3-kernel.sh
```

It checks the base commit/combined DMA changes and applies0004, refusing to overwrite an existing output configuration. If source is absent, follow only source preparation in step 2 of the tidl2 guide, then use this script without running that guide's build. The r47 base commit is c03783811916b255c974912b3fd2eceb30fa8146. Do not ignore source/patch mismatches.

Check configuration:

```bash
git -C kernel-work/linux diff --check
git -C kernel-work/linux apply --reverse --check \
 "$PWD/patches/0004-rpmsg-char-report-bound-local-endpoint-address.patch"
grep -E '^CONFIG_(RPMSG_CHAR|DMABUF_HEAPS_CARVEOUT|REMOTEPROC_TI_VISION_DMA_BUF)=' \
 kernel-work/out-tidl3/.config
```

Expect RPMSG_CHAR=m, DMABUF_HEAPS_CARVEOUT=y, REMOTEPROC_TI_VISION_DMA_BUF=y. Preserve previous tidl2 output/releases. Do not build tidl2 and tidl3 concurrently from the same source tree.

## 3. User starts the build

```bash
BUILD_JOBS=8 bash scripts/build-tidl3-kernel.sh
```

This starts compilation. A new out-tidl3 requires a full build. Reduce BUILD_JOBS to2/4 for available RAM. Duration was not measured. Progress is logged to kernel-work/tidl3-build.log.

The script runs olddefconfig, version/feature checks, Image.gz/modules builds, **local staging** modules_install, and image/config/System.map/checksum/tar packaging. modules_install targets stage-tidl3 inside the project, not the host OS or board. No SSH/scp/reboot/module-loading commands are present. The existing candidate DTB is retained.

On error, provide the final error log without uploading. An existing stage-tidl3 stops the script; inspect partial output rather than treating it as success. out-tidl3 can be reused on a build retry.

## 4. Post-build checks and next stage

```bash
find kernel-work/stage-tidl3 -name 'rpmsg_char.ko*' -print
(cd kernel-work/stage-tidl3 && sha256sum -c SHA256SUMS)
ls -lh kernel-work/6.18.39-arm64-k3-r47-tidl3-local-package.tar.gz
```

Provide tidl3-build.log and these checks. Finalize manual deployment after reviewing image/module versions and the package. **Do not attempt to deploy tidl3 files that do not yet exist.** Preserve tidl2 boot/kernel, noeth firmware, and SD recovery. Keep diagnostic-lib to verify positive matching raw src/returned endpt under the new kernel. No library rebuild or model requantization is needed.

Final gates:

1. Confirm actual tidl3 boot with uname and the entry marker.
2. Confirm existing heap/ioctl and noeth IPC functionality.
3. In the same05 run, verify raw src=-1/returned=0 is gone and the actual address is returned.
4. Require after tidl_session, after tidl_run, TIDL_BENCHMARK_OK; investigate any new failure before continuing.
5. After inference passes, validate separate C71x/MMA profiling evidence.
