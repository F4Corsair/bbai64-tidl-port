# MAIN R5F0_0 진단 펌웨어 수동 적용

## 적용 목적과 검사 결과

이번 펌웨어는 기존 EVM 설정을 유지하고 초기화 전후 `BBAI64:` 진단 표식만 추가한 **trace 후보**다. ETHFW를 끄는 수정은 포함하지 않는다. 빈 trace0로는 판단하기 어려웠던 IPC 이전 정지 위치를 확인한다. MAIN R5F0_0 파일 하나만 바꾸며 DT, 커널, extlinux.conf, MCU R5F 및 다른 DSP 펌웨어는 변경할 필요가 없다.

오프라인 검사 통과, 보드 실행 미검증 상태다.

- ARM ELF32, entry 0 및 코어 로컬 LOAD `[0, 0xa80)`은 기존과 같다. 로컬 주소 변환은 기존 R5F 드라이버 구성을 전제로 한다.
- 모든 DDR LOAD는 `[0xa2100000, 0xa4000000)` 안에 있으며 서로 중복되지 않는다.
- resource table은 기존 ELF와 바이트 단위로 같다. `.tracebuf`는 `0xa342bc00`, 크기 `0x80000`으로 같다.
- 주요 진단 문자열과 빌드 로그의 최종 링크를 확인했다.
- 새 ELF SHA256: `b95fb67b4f002ae533a2429be7e98e7e799f744c62c9731b1566eed3a7088163`.

`deploy-trace/`에 ELF·map·검사 JSON·SHA256SUMS를 묶었다. 보드에서 필요한 실행 파일은 `.out` 하나다. map과 JSON은 분석용이다. ELF가 약 13 MB인 것은 디버그 정보를 포함하기 때문이며 파일 크기 전체가 실행 메모리 사용량은 아니다. 현재 후보는 기존처럼 서명되지 않은 ELF 경로를 전제로 한다. HS 서명 이미지가 요구되거나 기존 파일 형식이 다르면 적용을 멈춘다.

## 1. 호스트에서 보드로 수동 복사

이후 명령은 사용자가 실행한다. Codex는 업로드나 보드 변경을 수행하지 않았다.

```bash
cd /home/corsair/Documents/sdk/ti_sdk_lab
(cd bbai64-porting/firmware-work/deploy-trace && sha256sum -c SHA256SUMS)
ssh beagle 'mkdir -p ~/bbai64-porting/firmware-trace'
scp bbai64-porting/firmware-work/deploy-trace/* \
  beagle:bbai64-porting/firmware-trace/
```

호스트 경로가 다르면 첫 cd만 바꾼다. 검사 실패 시 복사를 멈추고 현재 빌드 ELF를 다시 검증한다.

## 2. 보드에서 적용 전 조건 확인

```bash
cd ~/bbai64-porting/firmware-trace
sha256sum -c SHA256SUMS
cat /sys/class/remoteproc/remoteproc5/name
cat /sys/class/remoteproc/remoteproc5/firmware
readlink /lib/firmware/j7-main-r5f0_0-fw
sha256sum /lib/firmware/j7-main-r5f0_0-fw
```

기대값: `5c00000.r5f`, `j7-main-r5f0_0-fw`, 링크 대상 `bbai64-psdk-11.02/vx_app_rtos_linux_mcu2_0.out`, 기존 파일 해시 `6f99b5497f75be958d59d845d782b0ffa1503eb22c75b9b4f895d641b61ea1c2`. 다르면 아래 교체 명령을 실행하지 않는다. remoteproc 번호는 부팅에 따라 바뀔 수 있으므로 name을 기준으로 찾는다.

적용된 DT에서 해당 코어의 memory-region을 확인한다. 다음은 읽기 전용 검사다.

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

검사 실패 시 중단하고 오류와 노드 출력을 보존한다. 검사를 우회하려고 DT를 변경하지 않는다.

SD의 Linux 루트 파티션을 다른 컴퓨터에서 마운트하고 수정할 수 있는지 확인한다. UART가 없으므로 SSH가 끊기면 이 복구 수단이 필요하다. 전체 이미지 백업은 생략하더라도 이번에 교체할 펌웨어 링크는 되돌리기 위해 보존한다.

**2026-11-18 실기 추가 확인:** `/proc/cmdline`의 `bbai64_tidl.entry=tidl-kernel-test`와 `/boot/firmware/extlinux/extlinux.conf`를 대조했다. 현재 기본 항목 `tidl-kernel-test`는 tidl2 커널과 후보 DT를 지정하고 **initrd 지시문은 없다**. 따라서 현재 부트 구성에서는 외부 initramfs를 지정하지 않으며, `/boot/initrd.img-$(uname -r)` 파일 부재는 이번 펌웨어 시험의 중단 사유가 아니다. initramfs 생성·갱신 없이 3번 수동 배치로 진행할 수 있다. 이후 부트 항목에 initrd를 추가하거나 항목을 바꾸면 아래 검사를 다시 적용한다.

initramfs에 해당 펌웨어가 포함되어 있는지 확인한다.

```bash
command -v lsinitramfs
ls -l /boot/initrd.img-"$(uname -r)"
lsinitramfs /boot/initrd.img-"$(uname -r)" | grep -E 'j7-main-r5f0_0-fw|vx_app_rtos_linux_mcu2_0|bbai64-psdk-11.02'
```

일치 항목이 없으면 보통 루트 파일시스템에서 펌웨어를 읽는 경로로 진행할 수 있다. initramfs가 없으면 부트 항목에서 다른 initramfs를 사용하지 않는지 확인한다. 읽을 수 없거나 도구가 없거나 일치 항목이 나오면 중단하고 출력을 전달한다. 실제 부트 항목이 다른 initramfs를 쓰면 그 파일도 검사해야 한다. initramfs에 포함된 경우 별도 갱신이 필요할 수 있으므로 루트 파일시스템의 링크만으로 새 펌웨어 로드를 판단하지 않는다. 이 가이드는 initramfs를 자동 생성·교체하지 않는다.

## 3. 보드에서 수동 배치 및 링크 교체

**이 단계는 시스템 변경이다.** 위 조건을 모두 충족한 경우에만 실행한다. 새 파일을 별도 경로에 두고 기존 파일은 유지한다. 명령은 한 번만 실행하며 이전 시험의 파일이 있으면 중단한다.

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

예상 링크는 `bbai64-trace-mcu2-0/vx_app_rtos_linux_mcu2_0-trace.out`이고 해시는 위 새 ELF 값이다. 어느 명령이든 실패하면 재부팅하지 말고 상태를 확인한다. 파일 교체만으로 실행 중 코어의 펌웨어가 바뀌지는 않는다.

확인 후 사용자가 재부팅한다. remoteproc stop/start는 하지 않는다.

```bash
sudo reboot
```

## 4. 재부팅 후 진단 결과 수집

SSH 재접속 후 먼저 수집만 한다. Step 04가 생성하는 로그와 구분하여 부팅 직후 trace를 확보한다.

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

`running`만으로 합격은 아니다. `BBAI64:`의 마지막 before/after, rc 및 MCU2_0에 대응하는 port 13/21을 확인한다. virtio 번호는 고정하지 않는다.

| 마지막 도달 지점 | 다음 판단 |
|---|---|
| ETHFW before만 있거나 after rc 실패 | ETHFW 제외 후보 검토 |
| Sciclient/UDMA/메모리 등에서 정지 | 해당 초기화의 자원 조건 조사 |
| cpu_sync before만 있음 | 참여 코어·공유 동기화 영역 조사 |
| remote_service after까지 도달 | IPC 서비스 등록 확인 후 04 진행 |
| trace가 비어 있음 | 실행 이미지·main 이전·trace 주소와 캐시 가시성 조사. 빈 출력만으로 실행 정지를 확정하지 않음 |

IPC 서비스가 등록되고 trace에 명백한 초기화 실패가 없을 때만 실행한다.

```bash
sudo env RPMSG_LIB_DIR="$PWD/rpmsg-work/lib" \
  bash scripts/04-check-tidl-runtime.sh --init
```

04가 실패하면 05는 보류하고 `tidl-results/trace-firmware/`와 04 상세 로그를 전달한다. 이번 trace 후보는 원인 확인용이므로 기존 문제를 그대로 재현할 수 있다.

## 5. 복구

SSH가 가능하면 기존 링크로 되돌리고 재부팅한다. 다음 명령도 사용자 수동 실행이다.

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

SSH가 불가능하면 전원을 끄고 SD를 호스트에 연결한다. **실제로 부팅한 Linux 루트 파티션**을 마운트하고 아래 예의 `/media/corsair/rootfs`를 실제 마운트 경로로 바꾼다. 호스트 자신의 `/lib/firmware`를 수정하지 않는다.

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

기존 링크 대상은 상대 경로이므로 SD에서도 원래 대상으로 복원된다. SD가 실제 루트가 아니라 eMMC로 부팅한 환경이라면 이 복구 예는 적용되지 않는다. 해당 저장장치의 오프라인 복구 수단을 확보하기 전에는 시험하지 않는다.
