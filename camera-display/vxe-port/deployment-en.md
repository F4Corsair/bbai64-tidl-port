# BBAI64 VXE deployment and validation

[한국어](deployment-ko.md) · [VXE](README-en.md)

The built module and VXE DTB are both needed to test the encoder. Local modpost, link and both file hash checks passed. The user runs the steps below. Board deployment and encoding remain unverified.

## 1. Upload from host

Verify the artifacts and upload them to the board user’s home directory from the host.

```bash
cd /home/corsair/Documents/sdk/ti_sdk_lab/camera-display/vxe-port
(cd module-check && sha256sum -c SHA256SUMS)
(cd dtb-check && sha256sum -c SHA256SUMS)
ssh beagle 'mkdir -p ~/dev_test/vxe-port'
scp module-check/vxe-enc.ko dtb-check/bbai64-tidl-vxe.dtb beagle:dev_test/vxe-port/
```

## 2. Preflight on board

Check the baseline on the board. Proceed when you can select the boot menu from the console or recover the boot partition on another PC. Confirm the current entry uses the candidate base DTB and has no initrd or extra DT overlays. Stop on a hash, boot marker, mount or vermagic mismatch. The first vermagic field must match the running release.

```bash
bash <<'SH'
set -euo pipefail
cd "$HOME/dev_test/vxe-port"
k=6.18.39-arm64-k3-r47-tidl3
boot=/boot/firmware
conf=$boot/extlinux/extlinux.conf
[ "$(uname -r)" = "$k" ]
grep -wq 'bbai64_tidl.entry=tidl-kernel-test-3' /proc/cmdline
findmnt --mountpoint "$boot"
cat "$conf"
printf '%s  %s\n' \
  2042886e7ee5d4ee2dd78ce0c8420a8a4e2e42b302b533decaa561fb74253b51 vxe-enc.ko \
  e60858c8397c8255aab5add08dc06a1484c0d7c07ea0316ca4ce7f86c5813b1a bbai64-tidl-vxe.dtb \
  f155f7fb6f65a8f4ebc49a944e4b248a864ed359df4bd8ffdb4ffa4b426f6c1b "$boot/ti/k3-j721e-bbai64-tidl-candidate.dtb" \
  | sha256sum -c -
modinfo -F vermagic ./vxe-enc.ko
modinfo -F depends ./vxe-enc.ko
SH
```

## 3. Install and boot candidate

Install the module and new DTB on the board and back up the current boot configuration.

```bash
bash <<'SH'
set -euo pipefail
cd "$HOME/dev_test/vxe-port"
boot=/boot/firmware
conf=$boot/extlinux/extlinux.conf
modules=/lib/modules/6.18.39-arm64-k3-r47-tidl3
[ ! -e "$conf.pre-vxe" ]
[ ! -e "$boot/ti/bbai64-tidl-vxe.dtb" ]
[ ! -e "$modules/updates/vxe-enc.ko" ]
! modinfo -n vxe_enc 2>/dev/null
sudo cp -- "$conf" "$conf.pre-vxe"
sudo install -Dm644 vxe-enc.ko "$modules/updates/vxe-enc.ko"
sudo depmod -a 6.18.39-arm64-k3-r47-tidl3
sudo install -m644 bbai64-tidl-vxe.dtb "$boot/ti/bbai64-tidl-vxe.dtb"
SH
```

Edit `/boot/firmware/extlinux/extlinux.conf` directly on the board. Duplicate the existing `tidl-kernel-test-3` entry. Keep the existing default and boot entries.

| extlinux | Value for the new entry |
|---|---|
| `label` | `tidl-vxe-test` |
| `fdt` | `/ti/bbai64-tidl-vxe.dtb` |
| `append` | Copy the existing arguments and set `bbai64_tidl.entry=tidl-vxe-test` |
| `kernel` / `linux` | Copy the kernel directive and path from the existing entry |

After saving, run the read-only comparison below. Confirm the diff only adds the new entry, then run `sync` and `sudo reboot`. Select `tidl-vxe-test` once from the boot menu.

```bash
diff -u /boot/firmware/extlinux/extlinux.conf.pre-vxe /boot/firmware/extlinux/extlinux.conf
```

## 4. Probe and format checks

Check the candidate boot on the board. Expect `img,vxe384` and platform driver `img_enc`. Find the actual encoder node. Check NV12 with `v4l2-ctl -d /dev/videoN --list-formats-out` and H.264 with `--list-formats`. Stop and collect logs if the node, formats or GStreamer element are absent.

```bash
grep -w 'bbai64_tidl.entry=tidl-vxe-test' /proc/cmdline
test "$(uname -r)" = 6.18.39-arm64-k3-r47-tidl3
tr '\000' '\n' < /sys/firmware/devicetree/base/bus@100000/video-encoder@4200000/compatible
sudo modprobe vxe_enc
readlink -f /sys/bus/platform/devices/4200000.video-encoder/driver
v4l2-ctl --list-devices
gst-inspect-1.0 v4l2h264enc
```

## 5. Synthetic input test

Encode a synthetic source on the board. Require EOS within 60 seconds, 300 decodable 720p frames, and no encoder timeout or DMA error. The existing TIDL repeat test must also pass in the same boot. Proceed to camera integration after these checks pass.

```bash
cd "$HOME/dev_test/vxe-port"
set -o pipefail
timeout 60s gst-launch-1.0 -e videotestsrc is-live=true num-buffers=300 \
  '!' 'video/x-raw,format=NV12,width=1280,height=720,framerate=30/1' \
  '!' v4l2h264enc '!' h264parse \
  '!' 'video/x-h264,stream-format=byte-stream,alignment=au' \
  '!' filesink location=vxe-720p30.h264 2>&1 | tee gst-encode.log
sudo journalctl -k -b --no-pager > kernel-vxe.log
v4l2-ctl --list-devices > v4l2-devices.log
cat /proc/cmdline > boot-cmdline.log
```

## 6. Collect results

Collect the files from the host. If encoding failed before producing a file, copy the available logs individually.

```bash
mkdir -p camera-display/vxe-port/board-results
scp beagle:dev_test/vxe-port/{vxe-720p30.h264,gst-encode.log,kernel-vxe.log,v4l2-devices.log,boot-cmdline.log} \
  camera-display/vxe-port/board-results/
ffprobe -v error -select_streams v:0 -count_frames \
  -show_entries stream=codec_name,width,height,nb_read_frames \
  camera-display/vxe-port/board-results/vxe-720p30.h264
ffmpeg -v error -xerror -i camera-display/vxe-port/board-results/vxe-720p30.h264 -f null -
```

## 7. Recovery

Boot the original tidl3 entry and manually restore the contents of `extlinux.conf.pre-vxe` to `extlinux.conf`. An empty diff confirms the restore. Run `sync` and `sudo reboot`, then repeat the TIDL baseline check. If SSH is unavailable, power down and use another PC to restore `extlinux/extlinux.conf.pre-vxe` to `extlinux/extlinux.conf` on the actual boot partition.

```bash
diff -u /boot/firmware/extlinux/extlinux.conf.pre-vxe /boot/firmware/extlinux/extlinux.conf
```
