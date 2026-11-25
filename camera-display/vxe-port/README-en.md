# BBAI64 VXE port preparation

[한국어](README-ko.md) · [Feasibility assessment](preanalysis-en.md) · [Deployment guide](deployment-en.md) · [Work log](../worklog-en.md) · [Outcomes](../outcomes-en.md) · [Board results](results-en.md)

## Source and checks

- The Yocto meta-ti `11.02.11` tag resolves to `ea8c0b1cf1ab8a0b327e3feb1144c1ccf05b8278`. Its base recipe pins driver commit `0bcbb20af32ea13275b452f0e84f5a49966d0bf6`, which is checked out in `ti-source/`. The base recipe lists no patch in `SRC_URI`. Layer-specific bbappends used for the SDK image remain unverified. [Yocto release recipe](https://git.yoctoproject.org/meta-ti/tree/meta-ti-bsp/recipes-bsp/ti-img-encode-decode/ti-vxe-vxd-driver_6.12.bb?h=11.02.11)
- The pinned source's V4L2 file handle and platform remove branches match the r47 header signatures. The full build still needs to establish compatibility. The driver requests a 40-bit DMA mask. MTX firmware is incorporated through `fw_binaries/include_all_fw_variants.h` in `encoder/mtx_fwif.c`. Preserve the upstream license and payload notices.
- The [overlay](k3-j721e-bbai64-vxe.dtso) merged offline into the existing BBAI64 candidate DTB. The sorted decompiled trees differ by one encoder node. Outputs and verified checksums are under `generated/`. The merged DTB SHA256 is `e60858c8397c8255aab5add08dc06a1484c0d7c07ea0316ca4ce7f86c5813b1a`. Board probe and encode remain untested.

## User-run build

From the project root, use fresh output directories.

In a fresh workspace, run `git clone --branch scarthgap/k6.12 https://git.ti.com/git/multimedia/img-vxe-vxd.git camera-display/vxe-port/ti-source`, then check out the driver commit above in detached mode.

```bash
bash camera-display/vxe-port/prepare-dtb.sh camera-display/vxe-port/dtb-check
bash camera-display/vxe-port/build-modules.sh camera-display/vxe-port/module-check
(cd camera-display/vxe-port/module-check && sha256sum -c SHA256SUMS)
```

The [build script](build-modules.sh) checks the existing tidl3 build and matching compiler, then uses the TI external module build. TI's Makefile builds both modules. The script stages only `vxe-enc.ko`. Stop before deployment if the source, compiler, modpost or vermagic checks fail. Build execution remains with the user. Script syntax and the offline DT merge were verified.

After a successful build, use a separate boot entry and keep the prior DTB and boot entry. Follow the [acceptance criteria](preanalysis-en.md) for probe, synthetic NV12 encode, TIDL regression and D435i integration.
