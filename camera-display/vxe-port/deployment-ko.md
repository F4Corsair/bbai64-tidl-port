# BBAI64 VXE 배포 및 검증

[English](deployment-en.md) · [VXE](README-ko.md)

장치에서 H.264 인코더를 확인하려면 빌드한 모듈과 VXE DTB를 함께 적용한다. 로컬 빌드는 modpost와 링크를 통과했고 두 파일의 해시를 확인했다. 아래 명령은 사용자가 실행한다. 보드 적용과 인코딩은 미검증이다.

## 1. 호스트 전송

호스트에서 체크섬을 확인하고 두 파일을 사용자 홈으로 전송한다.

```bash
cd /home/corsair/Documents/sdk/ti_sdk_lab/camera-display/vxe-port
(cd module-check && sha256sum -c SHA256SUMS)
(cd dtb-check && sha256sum -c SHA256SUMS)
ssh beagle 'mkdir -p ~/dev_test/vxe-port'
scp module-check/vxe-enc.ko dtb-check/bbai64-tidl-vxe.dtb beagle:dev_test/vxe-port/
```

## 2. 보드 사전 확인

보드에서 기준선을 확인한다. 콘솔에서 부트 메뉴를 선택하거나 부트 파티션을 다른 PC에서 복구할 수 있을 때 진행한다. 기존 부트 항목이 후보 원본 DTB를 사용하고 initrd·추가 DT 오버레이가 없는지 확인한다. 해시, 부트 표식, 마운트 또는 vermagic이 다르면 중단한다. vermagic의 첫 필드는 실행 커널과 같아야 한다.

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

## 3. 설치 및 후보 부팅

보드에서 모듈과 새 DTB를 설치하고 현재 부트 설정을 백업한다.

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

보드에서 `/boot/firmware/extlinux/extlinux.conf`를 직접 편집한다. 기존 `tidl-kernel-test-3` 항목을 복제해 새 항목을 추가한다. 기존 기본값과 부트 항목은 유지한다.

| extlinux | 새 항목에 입력할 값 |
|---|---|
| `label` | `tidl-vxe-test` |
| `fdt` | `/ti/bbai64-tidl-vxe.dtb` |
| `append` | 기존 값을 복사하고 `bbai64_tidl.entry=tidl-vxe-test`만 변경 |
| `kernel` / `linux` | 기존 항목의 커널 경로 그대로 복사 |

저장 후 아래 읽기 전용 비교를 실행한다. 새 항목만 추가됐는지 확인하고 `sync`와 `sudo reboot`를 실행한다. 부트 메뉴에서 `tidl-vxe-test`를 한 번 선택한다.

```bash
diff -u /boot/firmware/extlinux/extlinux.conf.pre-vxe /boot/firmware/extlinux/extlinux.conf
```

## 4. Probe 및 형식 확인

후보로 부팅한 보드에서 확인한다. compatible은 `img,vxe384`, 바인딩 드라이버는 `img_enc`가 예상된다. 실제 인코더 노드를 찾아 `v4l2-ctl -d /dev/videoN --list-formats-out`의 NV12와 `--list-formats`의 H.264를 확인한다. 노드·포맷·GStreamer 요소가 없으면 로그를 확보하고 다음 단계로 넘어가지 않는다.

```bash
grep -w 'bbai64_tidl.entry=tidl-vxe-test' /proc/cmdline
test "$(uname -r)" = 6.18.39-arm64-k3-r47-tidl3
tr '\000' '\n' < /sys/firmware/devicetree/base/bus@100000/video-encoder@4200000/compatible
sudo modprobe vxe_enc
readlink -f /sys/bus/platform/devices/4200000.video-encoder/driver
v4l2-ctl --list-devices
gst-inspect-1.0 v4l2h264enc
```

## 5. 합성 입력 시험

보드에서 합성 영상을 먼저 인코딩한다. 60초 내 EOS, 디코딩 가능한 720p 300프레임, 인코더 timeout·DMA 오류 없음이 합격 기준이다. 같은 부팅에서 기존 TIDL 추론 반복 시험도 통과해야 한다. 별도 카메라 연동은 합격 후 진행한다.

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

## 6. 결과 수집

호스트에서 산출물과 로그를 수집한다. GStreamer 실패로 출력 파일이 없으면 존재하는 로그만 복사한다.

```bash
mkdir -p camera-display/vxe-port/board-results
scp beagle:dev_test/vxe-port/{vxe-720p30.h264,gst-encode.log,kernel-vxe.log,v4l2-devices.log,boot-cmdline.log} \
  camera-display/vxe-port/board-results/
ffprobe -v error -select_streams v:0 -count_frames \
  -show_entries stream=codec_name,width,height,nb_read_frames \
  camera-display/vxe-port/board-results/vxe-720p30.h264
ffmpeg -v error -xerror -i camera-display/vxe-port/board-results/vxe-720p30.h264 -f null -
```

## 7. 복구

보드에서 기존 tidl3 항목으로 부팅한 뒤 사용자가 백업을 직접 복원한다. `extlinux.conf.pre-vxe`의 내용을 원래 `extlinux.conf`에 복원하고 아래 비교에서 출력이 없으면 복원이 확인된 것이다. 이후 `sync` 및 `sudo reboot`를 실행해 기존 TIDL 검증을 반복한다. SSH가 불가능하면 전원을 끄고 다른 PC에서 실제 부트 파티션의 `extlinux/extlinux.conf.pre-vxe`를 `extlinux/extlinux.conf`로 복원한다.

```bash
diff -u /boot/firmware/extlinux/extlinux.conf.pre-vxe /boot/firmware/extlinux/extlinux.conf
```
