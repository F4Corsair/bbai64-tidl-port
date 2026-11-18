# tidl3 커널 사용자 수동 적용

로컬 패키지 checksum 전체, 커널 이미지 존재, rpmsg_char 모듈 vermagic `6.18.39-arm64-k3-r47-tidl3`를 확인했다. 빌드·패키징 완료, 보드 부팅·RPMsg 동작은 미검증이다. 빌드에는 cc33xx Wi-Fi debugfs.c:91의 기존 FORTIFY 경고 한 건이 있으며 RPMsg 수정 파일의 경고는 아니다. 경고의 원인 수정은 이번 범위 밖으로 남긴다.

읽기 전용 조사에서 보드는 tidl2, noeth 펌웨어이며 루트 여유 41 GiB, boot FAT 여유 177 MiB다. 새 DT나 펌웨어는 배치하지 않는다. UART가 없으므로 실제 부팅 SD를 다른 PC에서 수정할 수 있어야 한다. 모든 아래 명령은 사용자 수동 실행이다.

## 1. 호스트에서 업로드

```bash
cd /home/corsair/Documents/sdk/ti_sdk_lab/bbai64-porting
scp kernel-work/6.18.39-arm64-k3-r47-tidl3-local-package.tar.gz beagle:~/
```

## 2. 보드에서 압축 해제·검사

```bash
cd ~
sha256sum 6.18.39-arm64-k3-r47-tidl3-local-package.tar.gz
mkdir tidl3-package
# 이미 디렉터리가 있으면 중단하고 이전 내용을 먼저 확인한다.
tar --no-same-owner -xzf 6.18.39-arm64-k3-r47-tidl3-local-package.tar.gz -C tidl3-package
cd ~/tidl3-package
sha256sum -c SHA256SUMS
modinfo lib/modules/6.18.39-arm64-k3-r47-tidl3/kernel/drivers/rpmsg/rpmsg_char.ko.xz | grep vermagic
```

archive 해시는 `a6d82de14ca5e4deda6a142474abd968a9880f18de99eb76974c7380f797a3c4`여야 한다. 모든 checksum OK 및 vermagic tidl3가 아니면 중단한다.

## 3. 사용자 수동 설치

커널 이름을 분리하여 tidl2를 보존한다. 모듈을 실행 중에 강제로 교체하거나 언로드하지 않는다.

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

실패하면 재부팅하지 말고 출력을 확인한다. 기존 tidl2 모듈과 Image.gz는 덮어쓰지 않는다.

## 4. 새 부트 항목 초안 생성 및 확인

다음은 사용자 폴더에 설정 초안을 만든다. 기존 tidl2 항목을 남기고 동일한 DT/root 설정의 tidl3 항목을 추가한다.

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

차이는 default 변경과 새 항목 추가여야 한다. diff 종료 코드 1은 차이가 있음을 의미한다. 새 항목의 kernel은 tidl3, fdt는 기존 후보, append의 root는 원래 값, entry 표식은 tidl-kernel-test-3, initrd 미지정인지 확인한다. initramfs를 새로 만들 필요는 없다.

확인 후에만 적용한다.

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

## 5. 재접속 후 확인 및 진단

```bash
uname -r
cat /proc/cmdline
modinfo rpmsg_char | grep -E 'filename|vermagic'
ls /dev/dma_heap/
```

uname은 6.18.39-arm64-k3-r47-tidl3, cmdline에는 bbai64_tidl.entry=tidl-kernel-test-3, 모듈도 tidl3이며 Vision Apps heap이 있어야 한다. 다르면 05로 진행하지 않는다. noeth 펌웨어는 유지한다.

먼저 04에서 초기화 기능 유지를 확인하고 성공한 경우에만 05를 실행한다.

```bash
cd ~/bbai64-porting
sudo env RPMSG_LIB_DIR="$PWD/rpmsg-work/diagnostic-lib" bash scripts/04-check-tidl-runtime.sh --init
# 04 성공한 경우에만
sudo env RPMSG_LIB_DIR="$PWD/rpmsg-work/diagnostic-lib" \
 bash scripts/05-check-onnx-ep.sh \
 "$HOME/models/resnet18/model.onnx" "$HOME/models/resnet18/artifacts/" \
 "$HOME/models/resnet18/input.f32" 1.0
```

RPMSG_DIAG의 raw src와 returned endpt가 동일한 양수의 실제 주소인지, after tidl_session/after tidl_run/TIDL_BENCHMARK_OK가 나오는지 확인한다. raw=-1/returned=0이 계속되면 새 커널·모듈 사용 여부를 확인하고 반복하지 말고 로그를 전달한다. 새 오류라면 해당 단계를 분석한다. 최종 MMA 증거 확인은 별도로 필요하다.

## 6. 복구

SSH가 가능하면 extlinux.conf.pre-tidl3를 복원하고 재부팅한다. 새 모듈과 이미지는 삭제할 필요가 없다.

```bash
sudo cp /boot/firmware/extlinux/extlinux.conf.pre-tidl3 /boot/firmware/extlinux/extlinux.conf.restore
sudo mv -Tf /boot/firmware/extlinux/extlinux.conf.restore /boot/firmware/extlinux/extlinux.conf
sync
sudo reboot
```

SSH不可なら電源を切りSDを別PCに接続する。FATのブートパーティションを開き、extlinux/extlinux.conf.pre-tidl3をextlinux.confへ戻す。ホストの/bootを変更しない。正常にアンマウントしてSDを戻す。root が eMMC 等、調査時と異なる構成なら適用を止めて복구手順を見直す。
