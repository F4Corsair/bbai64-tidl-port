# User-Performed tidl3 Kernel Deployment

All local package checksums, the kernel image, and rpmsg_char vermagic `6.18.39-arm64-k3-r47-tidl3` were verified. Build/packaging is complete; board boot and RPMsg behavior remain Unverified at this stage. The build has one existing FORTIFY warning at cc33xx Wi-Fi debugfs.c:91, not in the modified RPMsg file. Fixing that warning is outside this change.

Read-only inspection found tidl2/noeth on the board, 41GiB free on root, and 177MiB on boot FAT. Do not install a new DT or firmware. Without UART, you must be able to edit the actual boot SD on another PC. All commands below are executed manually by the user.

## 1. Upload from the host

```bash
cd /home/corsair/Documents/sdk/ti_sdk_lab/bbai64-porting
scp kernel-work/6.18.39-arm64-k3-r47-tidl3-local-package.tar.gz beagle:~/
```

## 2. Extract and verify on the board

```bash
cd ~
sha256sum 6.18.39-arm64-k3-r47-tidl3-local-package.tar.gz
mkdir tidl3-package
# Stop if the directory exists and inspect its contents first.
tar --no-same-owner -xzf 6.18.39-arm64-k3-r47-tidl3-local-package.tar.gz -C tidl3-package
cd ~/tidl3-package
sha256sum -c SHA256SUMS
modinfo lib/modules/6.18.39-arm64-k3-r47-tidl3/kernel/drivers/rpmsg/rpmsg_char.ko.xz | grep vermagic
```

The archive hash must be `a6d82de14ca5e4deda6a142474abd968a9880f18de99eb76974c7380f797a3c4`. Stop unless all checksums pass and vermagic identifies tidl3.

## 3. Manual installation

Use a separate kernel name to preserve tidl2. Do not force-replace or unload active modules.

```bash
bash <<'SH'
set -euo pipefail
cd "$HOME/tidl3-package"
release=6.18.39-arm64-k3-r47-tidl3
[ ! -e "/lib/modules/$release" ]
[ ! -e "/boot/firmware/Image-$release.gz" ]
[ -r /boot/firmware/ti/k3-j721e-bbai64-tidl-candidate.dtb ]
sha256sum -c SHA256SUMS
sudo cp -a "lib/modules/$release" /lib/modules/
sudo install -m 0644 "boot/config-$release" /boot/
sudo install -m 0644 "boot/System.map-$release" /boot/
sudo depmod -a "$release"
sudo install -m 0644 "boot/Image-$release.gz" /boot/firmware/
cmp "boot/Image-$release.gz" "/boot/firmware/Image-$release.gz"
sync
SH
```

On failure, inspect the output without rebooting. Do not overwrite tidl2 modules or Image.gz.

## 4. Generate and inspect the proposed boot entry

Create the proposal in the user's directory. Keep the tidl2 entry and add tidl3 with the same DT/root configuration.

```bash
python3 - <<'PY'
from pathlib import Path
import re
p=Path('/boot/firmware/extlinux/extlinux.conf'); s=p.read_text()
assert 'label tidl-kernel-test-3' not in s
assert re.search(r'^default tidl-kernel-test$',s,re.M)
m=re.search(r'^label tidl-kernel-test\n.*?(?=^label |\Z)',s,re.M|re.S)
assert m
block=m.group()
assert '/Image-6.18.39-arm64-k3-r47-tidl2.gz' in block
assert not re.search(r'^\s*initrd\s',block,re.M)
new=block.replace('label tidl-kernel-test\n','label tidl-kernel-test-3\n',1).replace('Image-6.18.39-arm64-k3-r47-tidl2.gz','Image-6.18.39-arm64-k3-r47-tidl3.gz').replace('bbai64_tidl.entry=tidl-kernel-test','bbai64_tidl.entry=tidl-kernel-test-3')
s=re.sub(r'^default tidl-kernel-test$', 'default tidl-kernel-test-3',s,flags=re.M)
Path.home().joinpath('extlinux.tidl3.proposed').write_text(s.rstrip()+'\n\n'+new.rstrip()+'\n')
PY
diff -u /boot/firmware/extlinux/extlinux.conf ~/extlinux.tidl3.proposed
```

The diff should contain only the default change and new entry. diff exit 1 means differences were found. Check kernel=tidl3, fdt=existing candidate, unchanged append root, marker tidl-kernel-test-3, and no initrd. No new initramfs is needed.

Apply only after review.

```bash
bash <<'SH'
set -euo pipefail
conf=/boot/firmware/extlinux/extlinux.conf
[ ! -e "$conf.pre-tidl3" ]
[ ! -e "$conf.tidl3-next" ]
sudo cp "$conf" "$conf.pre-tidl3"
sudo cp "$HOME/extlinux.tidl3.proposed" "$conf.tidl3-next"
sudo mv -Tf "$conf.tidl3-next" "$conf"
cat "$conf"
sync
SH
sudo reboot
```

## 5. Checks and diagnosis after reconnecting

```bash
uname -r
cat /proc/cmdline
modinfo rpmsg_char | grep -E 'filename|vermagic'
ls /dev/dma_heap/
```

Require uname=6.18.39-arm64-k3-r47-tidl3, bbai64_tidl.entry=tidl-kernel-test-3 in cmdline, tidl3 modules, and the Vision Apps heap. Otherwise do not run05. Retain noeth firmware.

First confirm initialization with04; run05 only if it passes.

```bash
cd ~/bbai64-porting
sudo env RPMSG_LIB_DIR="$PWD/rpmsg-work/diagnostic-lib" bash scripts/04-check-tidl-runtime.sh --init
# Only if step04 passed
sudo env RPMSG_LIB_DIR="$PWD/rpmsg-work/diagnostic-lib" \
 bash scripts/05-check-onnx-ep.sh \
 "$HOME/models/resnet18/model.onnx" "$HOME/models/resnet18/artifacts/" \
 "$HOME/models/resnet18/input.f32" 1.0
```

Check that RPMSG_DIAG raw src and returned endpt are the same positive actual address, followed by after tidl_session/after tidl_run/TIDL_BENCHMARK_OK. If raw=-1/returned=0 persists, verify the active kernel/modules and provide logs rather than repeating runs. Investigate any new failure at its stage. Final MMA evidence remains a separate requirement.

## 6. Recovery

If SSH works, restore extlinux.conf.pre-tidl3 and reboot. There is no need to delete the new image/modules.

```bash
sudo cp /boot/firmware/extlinux/extlinux.conf.pre-tidl3 /boot/firmware/extlinux/extlinux.conf.restore
sudo mv -Tf /boot/firmware/extlinux/extlinux.conf.restore /boot/firmware/extlinux/extlinux.conf
sync
sudo reboot
```

If SSH fails, power off and connect the SD to another PC. On its FAT boot partition, restore extlinux/extlinux.conf from extlinux/extlinux.conf.pre-tidl3. Do not modify the host's /boot. Unmount cleanly before reinstalling the SD. If root is on eMMC or otherwise differs from the inspected configuration, stop and revise the recovery procedure.
