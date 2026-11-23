# Manual Deployment of MAIN R5F0_0 Diagnostic Firmware

## Purpose and checks

This **trace candidate** retains EVM settings and only adds BBAI64 initialization markers. It does not disable ETHFW. It identifies pre-IPC progress that an empty trace0 could not resolve. Only MAIN R5F0_0 changes; DT, kernel, extlinux.conf, MCU R5F, and other DSP firmware remain unchanged.

Offline checks passed; board execution is Unverified.

- ARM ELF32, entry0, and core-local LOAD [0,0xa80) match the original. Local translation assumes the existing R5F driver configuration.
- All DDR LOADs fit [0xa2100000,0xa4000000), without overlap.
- Resource-table bytes match the old ELF. .tracebuf stays at0xa342bc00 with size 0x80000.
- Key marker strings and final link completion were checked.
- New ELF SHA256: b95fb67b4f002ae533a2429be7e98e7e799f744c62c9731b1566eed3a7088163.

deploy-trace/ includes ELF, map, validation JSON, and SHA256SUMS. Only .out is needed for execution; map/JSON are analytical records. The approximately13MB ELF includes debug data and is not a measure of total runtime memory use. This candidate assumes the same unsigned-ELF loading path as before. Stop if an HS-signed image is required or the existing format differs.

## 1. Manual transfer from host

The user executes these commands; Codex did not upload or change the board.

```bash
cd /home/corsair/Documents/sdk/ti_sdk_lab
(cd bbai64-porting/firmware-work/deploy-trace && sha256sum -c SHA256SUMS)
ssh beagle 'mkdir -p ~/bbai64-porting/firmware-trace'
scp bbai64-porting/firmware-work/deploy-trace/* \
  beagle:bbai64-porting/firmware-trace/
```

Change only the initial cd if the host path differs. On failed validation, stop transfer and recheck the built ELF.

## 2. Board preconditions

```bash
cd ~/bbai64-porting/firmware-trace
sha256sum -c SHA256SUMS
cat /sys/class/remoteproc/remoteproc5/name
cat /sys/class/remoteproc/remoteproc5/firmware
readlink /lib/firmware/j7-main-r5f0_0-fw
sha256sum /lib/firmware/j7-main-r5f0_0-fw
```

Expect 5c00000.r5f, j7-main-r5f0_0-fw, link target bbai64-psdk-11.02/vx_app_rtos_linux_mcu2_0.out, and old hash6f99b5497f75be958d59d845d782b0ffa1503eb22c75b9b4f895d641b61ea1c2. Otherwise do not replace it. remoteproc numbering can change; identify by name.

Read-only check of the core's applied memory-region:

```bash
python3 - <<'PY'
from pathlib import Path
import struct
root=Path('/sys/firmware/devicetree/base')
cores=[p.parent for p in root.rglob('reg') if p.parent.name=='r5f@5c00000']
assert len(cores)==1, 'MCU2_0 DT node identification failed'
node=cores[0]
ph=struct.unpack('>'+str(len((node/'memory-region').read_bytes())//4)+'I',(node/'memory-region').read_bytes())
refs={}
for p in root.rglob('phandle'):
 b=p.read_bytes()
 if len(b)==4: refs[struct.unpack('>I',b)[0]]=p.parent
regions=[]
for h in ph:
 p=refs[h]; b=(p/'reg').read_bytes(); assert len(b)==16, 'Unexpected reg cells'
 ah,al,sh,sl=struct.unpack('>4I',b);start=(ah<<32)|al;size=(sh<<32)|sl
 regions.append((start,size));print(p.name,hex(start),hex(size))
assert regions[:2]==[(0xa2000000,0x100000),(0xa2100000,0x1f00000)], 'Unexpected memory-region mapping'
print('PASS: MCU2_0 DMA and firmware reservations match')
PY
```

On failure, preserve errors/node output and stop. Do not edit the DT to bypass validation.

Ensure another PC can mount/edit the SD Linux root partition. This is the recovery path without UART if SSH fails. Even without a whole-image backup, preserve the firmware link being replaced.

**Hardware follow-up, 2026-11-18:** /proc/cmdline marker bbai64_tidl.entry=tidl-kernel-test matches /boot/firmware/extlinux/extlinux.conf. The selected tidl-kernel-test uses tidl2/candidate DT and **has no initrd directive**. Thus no external initramfs is selected, and absence of /boot/initrd.img-$(uname -r) does not block this test. Proceed to step 3 without generating/updating initramfs. Repeat the check if the entry or initrd changes later.

Check whether the firmware is included in initramfs:

```bash
command -v lsinitramfs
ls -l /boot/initrd.img-"$(uname -r)"
lsinitramfs /boot/initrd.img-"$(uname -r)" | grep -E 'j7-main-r5f0_0-fw|vx_app_rtos_linux_mcu2_0|bbai64-psdk-11.02'
```

No matches normally allows the rootfs-loading path. If no initramfs file exists, confirm the entry does not use another one. Stop/report output if unreadable, tooling is absent, or matching firmware appears. Check any alternate initramfs actually selected. An embedded image may need a separate update; the rootfs symlink alone does not prove the new firmware was loaded. This guide does not automatically regenerate/replace initramfs.

## 3. Manual file installation and link replacement

**This changes the system.** Run only after all preconditions pass. Place the new file separately and preserve the original. Run once; stop if previous-test files exist.

```bash
bash <<'SH'
set -euo pipefail
cd "$HOME/bbai64-porting/firmware-trace"
sha256sum -c SHA256SUMS
fw=/lib/firmware/j7-main-r5f0_0-fw
old=/lib/firmware/j7-main-r5f0_0-fw.pre-trace
new=/lib/firmware/j7-main-r5f0_0-fw.trace-next
[ -L "$fw" ]
[ "$(readlink "$fw")" = 'bbai64-psdk-11.02/vx_app_rtos_linux_mcu2_0.out' ]
[ ! -e "$old" ] && [ ! -L "$old" ]
[ ! -e "$new" ] && [ ! -L "$new" ]
[ ! -e /lib/firmware/bbai64-trace-mcu2-0 ]
sudo cp -a --no-dereference "$fw" "$old"
sudo install -d -m 0755 /lib/firmware/bbai64-trace-mcu2-0
sudo install -m 0644 vx_app_rtos_linux_mcu2_0-trace.out \
  /lib/firmware/bbai64-trace-mcu2-0/vx_app_rtos_linux_mcu2_0-trace.out
cmp vx_app_rtos_linux_mcu2_0-trace.out \
  /lib/firmware/bbai64-trace-mcu2-0/vx_app_rtos_linux_mcu2_0-trace.out
sudo ln -s bbai64-trace-mcu2-0/vx_app_rtos_linux_mcu2_0-trace.out "$new"
sudo mv -Tf "$new" "$fw"
readlink "$fw"
sha256sum "$fw"
sync
SH
```

Expect bbai64-trace-mcu2-0/vx_app_rtos_linux_mcu2_0-trace.out and the new hash above. On any command failure, inspect before rebooting. Replacing a file does not replace firmware already running on a core.

After checks, the user reboots. Do not stop/start remoteproc.

```bash
sudo reboot
```

## 4. Collect diagnostics after reboot

Collect boot trace immediately after reconnecting, separately from logs created by04.

```bash
cd ~/bbai64-porting
mkdir -p tidl-results/trace-firmware
uname -a | tee tidl-results/trace-firmware/kernel.txt
for p in /sys/class/remoteproc/remoteproc*; do
  if [ "$(cat "$p/name")" = 5c00000.r5f ]; then
    r=${p##*/}
    cat "$p/name" "$p/state" "$p/firmware" \
      | tee tidl-results/trace-firmware/remoteproc.txt
    sudo cat "/sys/kernel/debug/remoteproc/$r/trace0" \
      | tee tidl-results/trace-firmware/trace0.txt
  fi
done
ls -l /sys/bus/rpmsg/devices/ | tee tidl-results/trace-firmware/rpmsg.txt
sudo dmesg | tee tidl-results/trace-firmware/dmesg.txt
readlink /lib/firmware/j7-main-r5f0_0-fw
sha256sum /lib/firmware/j7-main-r5f0_0-fw
```

running alone is not a pass. Inspect the final BBAI64 before/after pair, rc, and MCU2_0 ports13/21. Do not assume fixed virtio numbers.

| Last progress | Next check |
|---|---|
| ETHFW before only or failing after rc | Consider noeth |
| Sciclient/UDMA/memory stall | Investigate that initialization's resource requirements |
| cpu_sync before only | Inspect peers/shared synchronization memory |
| Through remote_service after | Check IPC services, then04 |
| Empty trace | Inspect loaded image, pre-main execution, trace address/cache visibility; emptiness alone does not prove a stall |

Run only when services are registered and trace shows no clear initialization failure.

```bash
sudo env RPMSG_LIB_DIR="$PWD/rpmsg-work/lib" \
  bash scripts/04-check-tidl-runtime.sh --init
```

If04 fails, defer05 and provide tidl-results/trace-firmware/ plus the detailed04 log. This diagnostic candidate may reproduce the original problem.

## 5. Recovery

With SSH, restore the previous link and reboot. The user executes these commands too.

```bash
sudo cp -a --no-dereference /lib/firmware/j7-main-r5f0_0-fw.pre-trace \
  /lib/firmware/j7-main-r5f0_0-fw.rollback-next
sudo mv -Tf /lib/firmware/j7-main-r5f0_0-fw.rollback-next \
  /lib/firmware/j7-main-r5f0_0-fw
readlink /lib/firmware/j7-main-r5f0_0-fw
sha256sum /lib/firmware/j7-main-r5f0_0-fw
sync
sudo reboot
```

Without SSH, power off and connect the SD to the host. Mount the **actual booted Linux root partition**, replacing /media/corsair/rootfs below. Do not modify the host's /lib/firmware.

```bash
rootfs=/media/corsair/rootfs
sudo test -f "$rootfs/etc/os-release"
sudo ls -l "$rootfs/lib/firmware/j7-main-r5f0_0-fw.pre-trace"
sudo cp -a --no-dereference "$rootfs/lib/firmware/j7-main-r5f0_0-fw.pre-trace" \
  "$rootfs/lib/firmware/j7-main-r5f0_0-fw.rollback-next"
sudo mv -Tf "$rootfs/lib/firmware/j7-main-r5f0_0-fw.rollback-next" \
  "$rootfs/lib/firmware/j7-main-r5f0_0-fw"
sudo readlink "$rootfs/lib/firmware/j7-main-r5f0_0-fw"
sync
sudo umount "$rootfs"
```

The original target is relative, so the link resolves correctly on the SD. This procedure does not apply if the board actually boots root from eMMC. Obtain an offline recovery method for the real storage device before testing.
