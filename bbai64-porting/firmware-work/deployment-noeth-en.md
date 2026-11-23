# Deploy the ETHFW-Disabled MAIN R5F0_0 Candidate

## Preparation and rationale

**Local build/offline validation complete; not uploaded or board-validated.** Cache-visible trace showed successful Sciclient/UDMA/memory initialization but no return after before appEthFwInit. Set BUILD_ENABLE_ETHFW=no to bypass that path and test progress into IPC. The exact failing ETHFW function is still Unverified.

BUILD_MCU_BOARD_DEPENDENCIES=yes preserves EVM display/video initialization, where another failure may appear. IPC peers remain MPU1_0, MCU2_0, MCU2_1, C6x_1, C6x_2, C7x_1. Build-CPU selection is distinct from runtime peers. Keep markers/cache writeback. Do not change kernel, DT, other firmware, or model.

### Completed checks

- TI Arm Clang4.0.4.LTS build/link passed without observed warnings/errors.
- DDR LOADs are within [0xa2100000,0xa4000000), with no overlap; entry/core-local area unchanged.
- Resource-table trace address moves from0xa342bc00 to0xa2932000; all other bytes match. ELF .tracebuf uses the new address and unchanged size 0x80000. Internal relocation requires no DT change.
- ETHFW markers and appEthFwInit/appEthFwEarlyInit map symbols are absent; IPC markers and ARM cache-writeback calls are present.
- eth0 uses am65-cpsw-nuss, a different path from ETHFW virtual Ethernet. This is not a guarantee that SSH survives the change; retain offline SD recovery.

New ELF SHA256: `567e257b39a2a6082c8a2394a3e49dea33b5add790449accae6d225f6bb5d695`.

The ELF, map, memory-validation JSON, build-configuration JSON, and SHA256SUMS are in deploy-noeth/. No user rebuild is needed. For reproduction, run build.sh PRIVATE_SDK noeth build on a fresh SDK copy; do not change the existing trace SDK's variant.

## 1. User uploads from the host

```bash
cd /home/corsair/Documents/sdk/ti_sdk_lab
(cd bbai64-porting/firmware-work/deploy-noeth && sha256sum -c SHA256SUMS)
ssh beagle 'mkdir -p ~/bbai64-porting/firmware-noeth'
scp bbai64-porting/firmware-work/deploy-noeth/* \
 beagle:bbai64-porting/firmware-noeth/
```

Require all checksums to pass. These and subsequent commands are executed by the user. Codex did not upload, modify, or reboot the board.

## 2. Check the current board configuration

```bash
cd ~/bbai64-porting/firmware-noeth
sha256sum -c SHA256SUMS
readlink /lib/firmware/j7-main-r5f0_0-fw
sha256sum /lib/firmware/j7-main-r5f0_0-fw
ls -l /lib/firmware/j7-main-r5f0_0-fw.pre-trace
```

Expect link bbai64-trace-wb-mcu2-0/vx_app_rtos_linux_mcu2_0-trace-wb.out and hash2d89af78e6034d1802b0c7ec198bfb1faa8dab661e34973469a0eae5c18a8040. Stop on mismatch. Preserve the .pre-trace SDK recovery link.

No additional changes are needed if DT, tidl2, and initrd-free tidl-kernel-test remain as before. Otherwise repeat memory-region/initramfs checks from the [previous guide](deployment-trace-en.md). Without UART, another PC must be able to repair the actual root SD.

## 3. Manual installation and link replacement

This changes the system. Save a new .pre-noeth link to the cache-writeback variant, leaving .pre-trace untouched.

```bash
bash <<'SH'
set -euo pipefail
cd "$HOME/bbai64-porting/firmware-noeth"
sha256sum -c SHA256SUMS
fw=/lib/firmware/j7-main-r5f0_0-fw
backup=/lib/firmware/j7-main-r5f0_0-fw.pre-noeth
next=/lib/firmware/j7-main-r5f0_0-fw.noeth-next
[ "$(readlink "$fw")" = 'bbai64-trace-wb-mcu2-0/vx_app_rtos_linux_mcu2_0-trace-wb.out' ]
[ "$(sha256sum "$fw" | cut -d' ' -f1)" = 2d89af78e6034d1802b0c7ec198bfb1faa8dab661e34973469a0eae5c18a8040 ]
[ -L /lib/firmware/j7-main-r5f0_0-fw.pre-trace ]
[ ! -e "$backup" ] && [ ! -L "$backup" ]
[ ! -e "$next" ] && [ ! -L "$next" ]
[ ! -e /lib/firmware/bbai64-noeth-mcu2-0 ]
sudo cp -a --no-dereference "$fw" "$backup"
sudo install -d -m 0755 /lib/firmware/bbai64-noeth-mcu2-0
sudo install -m 0644 vx_app_rtos_linux_mcu2_0-noeth.out \
 /lib/firmware/bbai64-noeth-mcu2-0/vx_app_rtos_linux_mcu2_0-noeth.out
cmp vx_app_rtos_linux_mcu2_0-noeth.out \
 /lib/firmware/bbai64-noeth-mcu2-0/vx_app_rtos_linux_mcu2_0-noeth.out
sudo ln -s bbai64-noeth-mcu2-0/vx_app_rtos_linux_mcu2_0-noeth.out "$next"
sudo mv -Tf "$next" "$fw"
readlink "$fw"
sha256sum "$fw"
sync
SH
```

Reboot only after the new hash matches. On error, inspect before rebooting. Do not stop/start remoteproc manually.

```bash
sudo reboot
```

## 4. Collect results after reconnecting

```bash
cd ~/bbai64-porting
mkdir -p tidl-results/noeth
readlink /lib/firmware/j7-main-r5f0_0-fw
sha256sum /lib/firmware/j7-main-r5f0_0-fw
for p in /sys/class/remoteproc/remoteproc*; do
 if [ "$(cat "$p/name")" = 5c00000.r5f ]; then
  r=${p##*/}
  cat "$p/name" "$p/state" "$p/firmware" | tee tidl-results/noeth/remoteproc.txt
  sudo cat "/sys/kernel/debug/remoteproc/$r/trace0" | tee tidl-results/noeth/trace0.txt
 fi
done
ls -l /sys/bus/rpmsg/devices/ | tee tidl-results/noeth/rpmsg.txt
sudo dmesg | tee tidl-results/noeth/dmesg.txt
```

Require no ETHFW markers, completion of after appIpcInit rc=0, after cpu_sync, after remote_service, and registration of MAIN R5F0_0 port 13 plus required port 21 services. virtio/remoteproc numbers may change; identify by core path. running alone is insufficient.

- No return from IPC: inspect IPC resources.
- Stalled cpu_sync: inspect peer cores/shared memory.
- Later display/video stall: inspect that stage and whether noboard is warranted.
- Trace still ends in ETHFW: check the new hash and actual loaded image first.

Once initialization/services meet these conditions, run04.

```bash
sudo env RPMSG_LIB_DIR="$PWD/rpmsg-work/lib" \
 bash scripts/04-check-tidl-runtime.sh --init
```

Read the reported detailed log with sudo cat and provide it. If04 fails, do not run05. Even after 04,05 must test the endpoint=0 fallback's actual DSP round trip.

## 5. Recovery

With SSH, revert to the previous cache-writeback diagnostic image:

```bash
sudo cp -a --no-dereference /lib/firmware/j7-main-r5f0_0-fw.pre-noeth \
 /lib/firmware/j7-main-r5f0_0-fw.rollback-noeth
sudo mv -Tf /lib/firmware/j7-main-r5f0_0-fw.rollback-noeth \
 /lib/firmware/j7-main-r5f0_0-fw
readlink /lib/firmware/j7-main-r5f0_0-fw
sha256sum /lib/firmware/j7-main-r5f0_0-fw
sync
sudo reboot
```

To restore original SDK firmware, use preserved .pre-trace instead of .pre-noeth. Without SSH, power off and attach the actual Linux-root SD to the host. Replace /media/corsair/rootfs with its real mount point.

```bash
rootfs=/media/corsair/rootfs
sudo test -f "$rootfs/etc/os-release"
sudo ls -l "$rootfs/lib/firmware/j7-main-r5f0_0-fw.pre-noeth"
sudo cp -a --no-dereference "$rootfs/lib/firmware/j7-main-r5f0_0-fw.pre-noeth" \
 "$rootfs/lib/firmware/j7-main-r5f0_0-fw.rollback-noeth"
sudo mv -Tf "$rootfs/lib/firmware/j7-main-r5f0_0-fw.rollback-noeth" \
 "$rootfs/lib/firmware/j7-main-r5f0_0-fw"
sudo readlink "$rootfs/lib/firmware/j7-main-r5f0_0-fw"
sync
sudo umount "$rootfs"
```

Modify the actual boot root medium. This SD example does not apply to an eMMC root. If an intermediate recovery link already exists, inspect rather than repeating commands.
