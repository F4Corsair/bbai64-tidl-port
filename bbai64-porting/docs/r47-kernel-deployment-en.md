# BBAI64 Test Kernel Deployment and Recovery

The test release is `6.18.39-arm64-k3-r47-tidl1`. It adds the Vision Apps DMA heap and address-query ioctl missing from the existing kernel. Retain the candidate DT and firmware set that passed01/02 on the board. Without UART, installation requires another PC capable of restoring extlinux on the SD's FAT boot partition.

The build started from the collected board kernel configuration. Cross tools were GCC 15 and binutils 2.46; Rust functionality was disabled. See config-delta.txt in the release directory for exact changes.

## Verify release files

Copy the complete local release/6.18.39-arm64-k3-r47-tidl1/ directory under the test board's home directory, then run:

```bash
cd ~/6.18.39-arm64-k3-r47-tidl1
sha256sum -c SHA256SUMS
uname -r
findmnt -no SOURCE,TARGET /
findmnt -no SOURCE,TARGET /boot/firmware
sudo cat /boot/firmware/extlinux/extlinux.conf
df -h / /boot/firmware
```

All hashes must match and the current kernel must be 6.18.39-arm64-k3-r47. The recovery entry is the working entry **pointing to a candidate DTB compatible with Vision Apps firmware**. This guide assumes the previously collected microSD boot setup without initrd. If the active entry uses initrd, after module installation create an image with `sudo update-initramfs -c -k 6.18.39-arm64-k3-r47-tidl1`, copy it under a new name to FAT, and set the test entry's initrd path accordingly.

## Install image and modules

The block below installs only new-release paths. Keeping the old kernel/module tree allows recovery by restoring extlinux. If this test release is already installed, verify hashes first.

```bash
(
  set -eu
  release=6.18.39-arm64-k3-r47-tidl1
  firmware=/boot/firmware
  config=$firmware/extlinux/extlinux.conf
  sha256sum -c SHA256SUMS
  test "$(uname -r)" = 6.18.39-arm64-k3-r47
  mountpoint -q "$firmware"
  test ! -e "/lib/modules/$release"
  test ! -e "$firmware/Image-$release.gz"
  sudo cp -n "$config" "$config.before-$release"
  sudo tar -xJf "modules-$release.tar.xz" -C /lib/modules
  sudo depmod "$release"
  sudo install -m 0644 "Image-$release.gz" "$firmware/"
)
```

On installation error, inspect partially installed new paths before editing extlinux. These commands do not automatically modify boot selection or reboot.

## Add an extlinux test entry

Use `sudoedit /boot/firmware/extlinux/extlinux.conf` to clone the **working candidate-DT entry**. Change label to tidl-kernel-test and kernel to /Image-6.18.39-arm64-k3-r47-tidl1.gz. Preserve fdt and the append root-device/console settings. Replace any earlier test tag with the tag below. Keep the new entry without initrd if the original entry had none.

```text
default tidl-kernel-test

label tidl-kernel-test
    kernel /Image-6.18.39-arm64-k3-r47-tidl1.gz
    fdt /ti/k3-j721e-bbai64-tidl-candidate.dtb
    append <preserve existing append arguments> bbai64_tidl.entry=tidl-kernel-test
```

Replace placeholders with actual existing arguments. Set fdt to the actual validated path. Keep a single global default line and preserve the working entry. Confirm that every path exists on microSD before the user reboots.

## Validate after reboot

```bash
uname -r
cd ~/bbai64-porting
bash scripts/01-check-boot-dt.sh --entry tidl-kernel-test
bash scripts/02-check-remoteproc.sh
ls -l /sys/class/dma_heap /dev/dma_heap
sudo bash scripts/03-check-ipc-dma.sh --allocate
```

- uname -r must be exactly 6.18.39-arm64-k3-r47-tidl1. Passing01/02 confirms the candidate DT, five running cores, and existing MCU attachment.
- carveout_vision_apps_shared-memories must appear in sysfs and /dev. Check DMA_HOST_OK and an address in [0xb8000000,0xd8000000) in03's detailed log. Even after host DMA passes,03 leaves the DSP round trip Unverified.
- On ERANGE or Invalid argument, record the actual remoteproc mapping and exporter name. For permission errors, check sudo and process CAP_SYS_RAWIO. Once DMA_HOST_OK is present, continue with04/05 in [runtime and ONNX validation](deployment-guide-en.md).

## Recovery

If SSH or test-kernel boot fails, power off and attach the SD to another PC. Restore extlinux/extlinux.conf from extlinux/extlinux.conf.before-6.18.39-arm64-k3-r47-tidl1 on FAT. This restores the **candidate-DT boot** used before adding the test kernel, so the current Vision Apps firmware can remain. Reverting to the stock BBAI64 DT also requires restoring the firmware links.
