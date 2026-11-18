# BBAI64 시험 커널 적용 및 복구

시험 릴리스는 `6.18.39-arm64-k3-r47-tidl1`이다. 기존 커널에 빠져 있던 Vision Apps DMA heap과 주소 조회 ioctl을 추가했다. 현재 보드에서 01과 02를 통과한 후보 DT 및 펌웨어 세트를 그대로 사용한다. UART 없이 적용하려면 SD를 다른 PC에서 열어 FAT 부트 파티션의 extlinux 설정을 복원할 수 있어야 한다.

빌드는 보드에서 수집한 커널 설정을 출발점으로 사용했다. 교차 도구는 GCC 15와 binutils 2.46이며 Rust 관련 기능은 이 빌드에서 제외됐다. 정확한 변경은 배포 폴더의 `config-delta.txt`에서 확인할 수 있다.

## 배포 파일 점검

로컬의 `release/6.18.39-arm64-k3-r47-tidl1/` 디렉터리를 그대로 시험 보드의 홈 디렉터리 아래에 복사한다. 시험 보드에서 다음을 실행한다.

```bash
cd ~/6.18.39-arm64-k3-r47-tidl1
sha256sum -c SHA256SUMS
uname -r
findmnt -no SOURCE,TARGET /
findmnt -no SOURCE,TARGET /boot/firmware
sudo cat /boot/firmware/extlinux/extlinux.conf
df -h / /boot/firmware
```

해시가 모두 일치하고 현재 커널이 `6.18.39-arm64-k3-r47`인지 확인한다. 현재 정상 부트 항목은 **Vision Apps 펌웨어와 호환되는 후보 DTB를 가리키는 항목**이다. 커널 시험 실패 시 해당 항목으로 돌아간다. 이 가이드는 기존에 수집한 microSD 부팅처럼 initrd 없이 부팅하는 구성을 기준으로 한다. 현재 사용 중인 항목에 활성 `initrd`가 있다면 모듈 설치 후 `sudo update-initramfs -c -k 6.18.39-arm64-k3-r47-tidl1`로 새 릴리스용 이미지를 생성한다. 그 파일을 FAT 부트 파티션에 새 이름으로 복사하고 시험 항목의 `initrd` 경로를 맞춘다.

## 이미지와 모듈 설치

다음 블록은 새 릴리스 경로만 설치한다. 기존 커널과 모듈 트리를 유지하면 extlinux 설정만 되돌려 복구할 수 있다. 동일 시험 릴리스가 이미 설치된 경우 파일 해시를 먼저 확인한다.

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

설치 중 오류가 발생하면 extlinux 설정을 편집하기 전에 새 경로의 부분 설치를 점검한다. 부트 설정 자동 변경이나 재부팅은 위 명령에 포함되지 않는다.

## extlinux 시험 항목 추가

`sudoedit /boot/firmware/extlinux/extlinux.conf`로 현재 **정상 동작한 후보 DT 부트 항목**을 복제한다. 복제한 항목의 `label`을 `tidl-kernel-test`, `kernel`을 `/Image-6.18.39-arm64-k3-r47-tidl1.gz`로 변경한다. 현재 항목의 `fdt`와 `append`의 루트 장치·콘솔 설정을 유지하고, 기존 시험 태그가 있다면 아래 새 태그로 교체한다. initrd가 없는 기존 항목은 새 항목도 그대로 유지한다.

```text
default tidl-kernel-test

label tidl-kernel-test
    kernel /Image-6.18.39-arm64-k3-r47-tidl1.gz
    fdt /ti/k3-j721e-bbai64-tidl-candidate.dtb
    append <기존 append 인자 유지> bbai64_tidl.entry=tidl-kernel-test
```

위의 자리표시자는 실제 기존 인자로 바꾼다. `fdt`는 현재 적용해 성공한 실제 경로와 맞춘다. 전역 `default`는 한 줄만 두고, 정상 항목은 보존한다. 설정의 경로에 실제 파일이 있고 대상이 microSD인지 확인한 뒤 사용자가 재부팅한다.

## 재부팅 후 검증

```bash
uname -r
cd ~/bbai64-porting
bash scripts/01-check-boot-dt.sh --entry tidl-kernel-test
bash scripts/02-check-remoteproc.sh
ls -l /sys/class/dma_heap /dev/dma_heap
sudo bash scripts/03-check-ipc-dma.sh --allocate
```

- `uname -r`은 정확히 `6.18.39-arm64-k3-r47-tidl1`이어야 한다. 01과 02가 성공하면 후보 DT 적용, 코어 5개의 기동 및 기존 MCU attach를 확인한 것이다.
- `carveout_vision_apps_shared-memories`가 sysfs와 `/dev`에 나타나야 한다. 03의 상세 로그에서 `DMA_HOST_OK`와 기대 범위 `[0xb8000000,0xd8000000)`의 주소를 확인한다. 03은 호스트 DMA가 통과해도 DSP 왕복을 미검증으로 보고한다.
- 주소 조회가 `ERANGE` 또는 `Invalid argument`로 실패하면 실제 remoteproc 매핑과 exporter 이름을 로그에 남긴다. 권한 오류는 sudo 실행 여부와 프로세스의 `CAP_SYS_RAWIO`를 확인한다. 03에서 `DMA_HOST_OK`가 확인되면 [런타임 및 ONNX 검증](deployment-guide-ko.md)의 04와 05를 진행한다.

## 복구

SSH 연결이 실패하거나 시험 커널이 부팅되지 않으면 전원을 끄고 SD를 다른 PC에 연결한다. FAT 부트 파티션의 `extlinux/extlinux.conf.before-6.18.39-arm64-k3-r47-tidl1`을 `extlinux/extlinux.conf`로 되돌린다. 백업은 시험 커널 추가 전의 **후보 DT 부팅**을 복구하므로 현재의 Vision Apps 펌웨어 세트를 유지할 수 있다. 기본 BBAI64 DT로도 되돌릴 경우에는 시험용 펌웨어 링크를 함께 복구해야 한다.
