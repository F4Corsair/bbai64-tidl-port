# ETHFW 제외 MAIN R5F0_0 후보 적용 가이드

## 준비 상태와 변경 이유

**로컬 빌드·오프라인 검사 완료 / 보드 미업로드·동작 미검증.** 캐시 반영 trace에서 Sciclient·UDMA·메모리 초기화는 성공했고 `before appEthFwInit` 뒤 반환이 없었다. 이번에는 `BUILD_ENABLE_ETHFW=no`로 ETHFW 초기화 경로를 제외해 IPC 초기화까지 진행되는지 확인한다. ETHFW 내부의 정확한 실패 함수는 아직 미확인이다.

`BUILD_MCU_BOARD_DEPENDENCIES=yes`를 유지하므로 EVM 디스플레이·영상 관련 초기화는 남는다. 그 단계에 새 장애가 나타날 수 있다. IPC peer는 MPU1_0, MCU2_0, MCU2_1, C6x_1, C6x_2, C7x_1로 기존 SDK 설정을 유지했다. 빌드 대상 CPU 선택과 런타임 peer 목록은 별개다. 진단 표식과 R5F trace 캐시 반영도 유지한다. 커널·DT·다른 코어 펌웨어·모델 변경은 하지 않는다.

### 완료한 검사

- TI Arm Clang 4.0.4.LTS 빌드·링크 성공, 빌드 로그에서 warning/error 미관측.
- ELF DDR LOAD가 [0xa2100000,0xa4000000) 내부이며 LOAD 간 중복 없음. 코어 로컬 영역·entry는 기존과 동일.
- resource table의 trace 주소가 `0xa342bc00`에서 `0xa2932000`으로 변경됨. 나머지 바이트는 기존과 같다. ELF `.tracebuf`도 새 주소이며 크기는 `0x80000`으로 일치한다. 내부 재배치이므로 DT 변경 불필요.
- ETHFW 초기화 진단 문자열 부재, ELF map에서 appEthFwInit/appEthFwEarlyInit 심볼 부재, IPC 진단 문자열 및 ARM 캐시 반영 호출 존재 확인.
- 보드의 현재 eth0 드라이버는 `am65-cpsw-nuss`로 확인했다. ETHFW 가상 Ethernet과 다른 드라이버 경로지만, 이번 변경 뒤 SSH 연결 보존을 보장하는 근거로 확대하지 않는다. SD 오프라인 복구를 유지한다.

새 ELF SHA256: `567e257b39a2a6082c8a2394a3e49dea33b5add790449accae6d225f6bb5d695`

결과물은 `deploy-noeth/`의 ELF, map, 메모리 검사 JSON, 빌드 설정 JSON, SHA256SUMS다. 사용자는 다시 빌드할 필요가 없다. 재현 시에는 fresh SDK 복사본에서 `build.sh PRIVATE_SDK noeth build`를 사용한다. 기존 trace SDK의 variant를 바꾸지 않는다.

## 1. 호스트에서 사용자 수동 업로드

```bash
cd /home/corsair/Documents/sdk/ti_sdk_lab
(cd bbai64-porting/firmware-work/deploy-noeth && sha256sum -c SHA256SUMS)
ssh beagle 'mkdir -p ~/bbai64-porting/firmware-noeth'
scp bbai64-porting/firmware-work/deploy-noeth/* \
 beagle:bbai64-porting/firmware-noeth/
```

모든 checksum이 OK여야 한다. 이 명령부터는 사용자가 직접 수행한다. Codex는 보드 업로드·변경·재부팅을 수행하지 않았다.

## 2. 보드에서 현재 상태 확인

```bash
cd ~/bbai64-porting/firmware-noeth
sha256sum -c SHA256SUMS
readlink /lib/firmware/j7-main-r5f0_0-fw
sha256sum /lib/firmware/j7-main-r5f0_0-fw
ls -l /lib/firmware/j7-main-r5f0_0-fw.pre-trace
```

예상 현재 링크는 `bbai64-trace-wb-mcu2-0/vx_app_rtos_linux_mcu2_0-trace-wb.out`, 해시는 `2d89af78e6034d1802b0c7ec198bfb1faa8dab661e34973469a0eae5c18a8040`이다. 다르면 중단한다. `.pre-trace` SDK 복구 링크를 보존한다.

기존과 같은 DT·tidl2 커널·initrd 없는 tidl-kernel-test 부트 설정을 유지한 경우 추가 변경이 필요 없다. 설정을 바꿨다면 [이전 적용 가이드](deployment-trace-ko.md)의 memory-region·initramfs 검사를 먼저 반복한다. UART가 없으므로 실제 루트 SD를 다른 컴퓨터에서 수정할 수 있어야 한다.

## 3. 보드에서 수동 배치·교체

시스템 변경 단계다. 기존 캐시 반영 진단판으로 돌아갈 `.pre-noeth` 링크를 새로 보존하며 `.pre-trace`는 건드리지 않는다.

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

새 해시와 일치할 때만 다음을 실행한다. 오류가 나면 재부팅하지 말고 상태를 확인한다. remoteproc stop/start는 수행하지 않는다.

```bash
sudo reboot
```

## 4. 재접속 후 결과 수집

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

합격 기준은 ETHFW 진단 표식 없이 `after appIpcInit rc=0`, `after cpu_sync`, `after remote_service`까지 진행하고, MAIN R5F0_0의 port 13 및 필요한 코어의 port 21 서비스가 등록되는 것이다. virtio/remoteproc 번호는 바뀔 수 있어 코어 경로를 확인한다. running만으로 성공을 판단하지 않는다.

- IPC 진입 후 반환이 없으면 IPC 초기화 자원을 조사한다.
- cpu_sync에서 멈추면 다른 참여 코어·공유 메모리를 조사한다.
- 이후 영상·디스플레이 초기화에서 멈추면 해당 단계와 noboard 후보 필요성을 검토한다.
- trace가 이전처럼 ETHFW에서 끝나면 새 이미지 해시·실제 로드부터 확인한다.

위 초기화·서비스 등록이 충족됐을 때 04를 실행한다.

```bash
sudo env RPMSG_LIB_DIR="$PWD/rpmsg-work/lib" \
 bash scripts/04-check-tidl-runtime.sh --init
```

출력에 나온 상세 로그를 `sudo cat`으로 읽어 전달한다. 04 실패 시 05를 수행하지 않는다. 04 성공 이후에도 endpoint=0 fallback의 실제 DSP 왕복은 05에서 검증해야 한다.

## 5. 복구

SSH가 가능하면 직전 캐시 반영 진단판으로 되돌린다.

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

SDK 원래 펌웨어로 돌아가려면 `.pre-noeth` 대신 보존한 `.pre-trace`를 사용한다. SSH가 불가능하면 전원을 끄고 실제 Linux 루트 SD를 호스트에 연결한다. 다음 `/media/corsair/rootfs`는 실제 마운트 위치로 바꾼다.

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

실제로 부팅한 루트 저장장치를 수정해야 한다. eMMC 루트라면 이 SD 복구 예를 그대로 적용하지 않는다. 중간 복구 링크가 이미 존재하면 명령을 반복하지 말고 상태를 확인한다.
