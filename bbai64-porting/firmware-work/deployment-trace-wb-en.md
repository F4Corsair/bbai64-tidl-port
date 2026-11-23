# Upload and Apply Cache-Visible Diagnostic Firmware

## Change and checks

**Built locally; board behavior Unverified.** This candidate diagnoses the initialization stall rather than directly fixing IPC. Keep the earlier trace variant's ETHFW/board settings and memory map. No kernel, DT, model, or other-core firmware changes.

0002-r5-trace-cache-writeback.patch writes back data logged by R5F Ipc_Trace_printf with CSL_armR5CacheWb(..., true). This PDK function is scheduler-independent and performs DMB/cache clean/DSB, so it is used for early main markers too. Split writes into two ranges on ring wrap. Do not apply to C66x/C71x. Existing formatting/concurrent-call behavior is unchanged; this is not a general logging-system redesign.

- MCU2_0 build/link with TI Arm Clang4.0.4.LTS passed without observed warnings/errors.
- DDR LOADs are inside [0xa2100000,0xa4000000), without overlap.
- Resource-table bytes and trace layout match the original SDK ELF.
- ARM Ipc_Trace_printf code calls CSL_armR5CacheWb.
- Mock tests covered contiguous writes, wrap splitting, and empty output. Board cache visibility/IPC remain post-reboot tests.

New ELF SHA256:
`2d89af78e6034d1802b0c7ec198bfb1faa8dab661e34973469a0eae5c18a8040`.

Records: trace-wb-build.log, trace-wb-disassembly.txt, deploy-trace-wb/trace-wb-elf-validation.json. prepare.py now copies the original SDK and applies0001/0002 in order. No user rebuild is needed for this set.

## 1. User upload from the host

```bash
cd /home/corsair/Documents/sdk/ti_sdk_lab
(cd bbai64-porting/firmware-work/deploy-trace-wb && sha256sum -c SHA256SUMS)
ssh beagle 'mkdir -p ~/bbai64-porting/firmware-trace-wb'
scp bbai64-porting/firmware-work/deploy-trace-wb/* \
  beagle:bbai64-porting/firmware-trace-wb/
```

Require all checksums to pass. Distinguish old deploy-trace from new deploy-trace-wb. The user executes all commands; Codex did not apply this to the board.

## 2. Board prerequisites/current files

```bash
cd ~/bbai64-porting/firmware-trace-wb
sha256sum -c SHA256SUMS
readlink /lib/firmware/j7-main-r5f0_0-fw
sha256sum /lib/firmware/j7-main-r5f0_0-fw
ls -l /lib/firmware/j7-main-r5f0_0-fw.pre-trace
```

Expect link bbai64-trace-mcu2-0/vx_app_rtos_linux_mcu2_0-trace.out and previous hash b95fb67b4f002ae533a2429be7e98e7e799f744c62c9731b1566eed3a7088163. Stop otherwise. Do not overwrite .pre-trace, which restores the original SDK firmware.

Keep the same DT/kernel/boot entry. The inspected tidl-kernel-test has no initrd; no initramfs update is needed if unchanged. If boot selection changed, repeat DT/initramfs checks in the [previous guide](deployment-trace-en.md). Preserve recovery by editing the SD on another PC.

## 3. Install the new file and replace the link

This changes the system. Preserve both old diagnostics and SDK recovery links. Use this block rather than rerunning step 3 of the earlier guide.

```bash
bash <<'SH'
set -euo pipefail
cd "$HOME/bbai64-porting/firmware-trace-wb"
sha256sum -c SHA256SUMS
fw=/lib/firmware/j7-main-r5f0_0-fw
next=/lib/firmware/j7-main-r5f0_0-fw.wb-next
[ "$(readlink "$fw")" = 'bbai64-trace-mcu2-0/vx_app_rtos_linux_mcu2_0-trace.out' ]
[ "$(sha256sum "$fw" | cut -d' ' -f1)" = b95fb67b4f002ae533a2429be7e98e7e799f744c62c9731b1566eed3a7088163 ]
[ -L /lib/firmware/j7-main-r5f0_0-fw.pre-trace ]
[ ! -e "$next" ] && [ ! -L "$next" ]
[ ! -e /lib/firmware/bbai64-trace-wb-mcu2-0 ]
sudo install -d -m 0755 /lib/firmware/bbai64-trace-wb-mcu2-0
sudo install -m 0644 vx_app_rtos_linux_mcu2_0-trace-wb.out \
 /lib/firmware/bbai64-trace-wb-mcu2-0/vx_app_rtos_linux_mcu2_0-trace-wb.out
cmp vx_app_rtos_linux_mcu2_0-trace-wb.out \
 /lib/firmware/bbai64-trace-wb-mcu2-0/vx_app_rtos_linux_mcu2_0-trace-wb.out
sudo ln -s bbai64-trace-wb-mcu2-0/vx_app_rtos_linux_mcu2_0-trace-wb.out "$next"
sudo mv -Tf "$next" "$fw"
readlink "$fw"
sha256sum "$fw"
sync
SH
```

Reboot only if the new hash matches. On failure, inspect before rebooting. Do not stop/start remoteproc.

```bash
sudo reboot
```

## 4. Collect trace first after reconnecting

Do this before repeating04 and provide results. Enter the sudo password in your terminal; tee makes saved output readable by the ordinary account.

```bash
cd ~/bbai64-porting
mkdir -p tidl-results/trace-wb
readlink /lib/firmware/j7-main-r5f0_0-fw
sha256sum /lib/firmware/j7-main-r5f0_0-fw
for p in /sys/class/remoteproc/remoteproc*; do
 if [ "$(cat "$p/name")" = 5c00000.r5f ]; then
  r=${p##*/}
  cat "$p/name" "$p/state" "$p/firmware" | tee tidl-results/trace-wb/remoteproc.txt
  sudo cat "/sys/kernel/debug/remoteproc/$r/trace0" | tee tidl-results/trace-wb/trace0.txt
 fi
done
ls -l /sys/bus/rpmsg/devices/ | tee tidl-results/trace-wb/rpmsg.txt
sudo dmesg | tee tidl-results/trace-wb/dmesg.txt
```

- before appUdmaInit without after: investigate UDMA first.
- after appUdmaInit rc=0 followed by an ETHFW stall: consider noeth.
- before cpu_sync without after: investigate peers/synchronization memory.
- Still empty/truncated: reassess diagnostic visibility; do not conclude from the tail alone.
- Once synchronization/remote-service setup completes and MCU2_0 services are registered, run updated04. On failure, defer05.

```bash
sudo env RPMSG_LIB_DIR="$PWD/rpmsg-work/lib" \
 bash scripts/04-check-tidl-runtime.sh --init
# Read the actual log file reported by the command.
# sudo cat tidl-results/04-check-tidl-runtime.ACTUAL_NAME.log
```

## 5. Recovery

Use the unchanged .pre-trace commands in [step 5 of the previous guide](deployment-trace-en.md) for original SDK firmware. Without SSH, attach the actual root SD to the host and repair the link as described there.

To return only to the immediately preceding diagnostic image:

```bash
sudo ln -s bbai64-trace-mcu2-0/vx_app_rtos_linux_mcu2_0-trace.out \
 /lib/firmware/j7-main-r5f0_0-fw.return-trace
sudo mv -Tf /lib/firmware/j7-main-r5f0_0-fw.return-trace \
 /lib/firmware/j7-main-r5f0_0-fw
sync
sudo reboot
```

If an intermediate link exists, inspect rather than rerunning. All diagnostic variants still require board validation and do not guarantee inference.
