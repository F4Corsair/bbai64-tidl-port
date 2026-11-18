# 캐시 반영 진단 펌웨어 업로드·적용 가이드

## 이번 변경과 검사 결과

**로컬 빌드 완료, 보드 동작 미검증.** 이번 후보는 IPC 장애를 직접 해결하는 펌웨어가 아니라 정확한 초기화 정지 위치를 확인하는 진단판이다. 이전 trace 후보의 ETHFW/보드 옵션과 메모리 맵은 유지한다. 커널·DT·모델·다른 코어 펌웨어는 변경하지 않는다.

`0002-r5-trace-cache-writeback.patch`는 R5F의 Ipc_Trace_printf가 기록한 영역을 `CSL_armR5CacheWb(..., true)`로 반영한다. SDK PDK의 이 함수는 OS 스케줄러에 의존하지 않으며 DMB/캐시 clean/DSB를 수행하므로 main 초기 표식에도 사용한다. 링 버퍼 끝을 넘으면 두 구간으로 나누어 반영한다. C66x/C71x용으로 적용하지 않는다. 기존 출력 함수의 동시 호출 처리와 포맷 동작은 그대로이므로 범용 로그 시스템 개선으로 보장하는 것은 아니다.

- TI Arm Clang 4.0.4.LTS로 MCU2_0 빌드·링크 완료, 빌드 로그에서 warning/error 미관측.
- ELF DDR LOAD가 [0xa2100000,0xa4000000) 내부, LOAD 간 중복 없음.
- resource table은 기존 SDK ELF와 바이트 단위로 같고 trace 배치도 같다.
- 실제 ARM 코드의 Ipc_Trace_printf에서 CSL_armR5CacheWb 호출 확인.
- 모의 cache API 검사에서 일반 기록·링 끝 분할·빈 출력의 반영 범위 확인. 실제 보드 캐시 가시성과 IPC 통과는 재부팅 후 검증한다.

새 ELF SHA256:
`2d89af78e6034d1802b0c7ec198bfb1faa8dab661e34973469a0eae5c18a8040`

빌드·검사 기록: `trace-wb-build.log`, `trace-wb-disassembly.txt`, `deploy-trace-wb/trace-wb-elf-validation.json`. 필요하면 `prepare.py`는 이제 원본 SDK 복사 후 0001과 0002를 순서대로 적용한다. 사용자는 이번에 다시 빌드할 필요가 없다.

## 1. 호스트에서 사용자 수동 업로드

```bash
cd /home/corsair/Documents/sdk/ti_sdk_lab
(cd bbai64-porting/firmware-work/deploy-trace-wb && sha256sum -c SHA256SUMS)
ssh beagle 'mkdir -p ~/bbai64-porting/firmware-trace-wb'
scp bbai64-porting/firmware-work/deploy-trace-wb/* \
  beagle:bbai64-porting/firmware-trace-wb/
```

전체 checksum이 OK여야 한다. 이전 deploy-trace 폴더와 새 deploy-trace-wb를 혼동하지 않는다. 이하 명령도 사용자가 직접 실행하며 Codex는 보드에 적용하지 않았다.

## 2. 보드에서 사전 조건과 현재 파일 확인

```bash
cd ~/bbai64-porting/firmware-trace-wb
sha256sum -c SHA256SUMS
readlink /lib/firmware/j7-main-r5f0_0-fw
sha256sum /lib/firmware/j7-main-r5f0_0-fw
ls -l /lib/firmware/j7-main-r5f0_0-fw.pre-trace
```

예상 현재 링크는 `bbai64-trace-mcu2-0/vx_app_rtos_linux_mcu2_0-trace.out`, 이전 진단 ELF 해시는 `b95fb67b4f002ae533a2429be7e98e7e799f744c62c9731b1566eed3a7088163`이다. 다르면 중단한다. 기존 `.pre-trace`는 SDK 원래 펌웨어로 돌아가기 위한 링크이므로 덮어쓰지 않는다.

이전 시험과 같은 DT·커널·부트 항목을 유지해야 한다. 이미 확인한 tidl-kernel-test 항목에는 initrd가 없으므로 그 설정이 그대로면 initramfs 갱신은 필요 없다. 부트 항목을 바꿨다면 [이전 가이드](deployment-trace-ko.md)의 DT·initramfs 검사를 다시 수행한다. SD를 다른 컴퓨터에서 수정하는 복구 수단을 유지한다.

## 3. 보드에서 새 파일 배치와 링크 교체

이 명령은 시스템 변경이다. 기존 진단 파일과 SDK 복구 링크를 모두 남긴다. 기존 가이드 3번을 다시 실행하지 말고 아래를 사용한다.

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

해시가 새 값과 일치할 때만 재부팅한다. 실패하면 재부팅하지 말고 오류를 확인한다. remoteproc stop/start는 하지 않는다.

```bash
sudo reboot
```

## 4. 재접속 후 trace 먼저 수집

04번을 반복하기 전에 아래를 실행하고 결과를 전달한다. sudo cat은 사용자 터미널에서 암호를 입력한다. tee로 만든 수집 파일은 일반 계정에서도 읽을 수 있다.

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

- `before appUdmaInit` 이후 after가 없으면 UDMA 경로를 우선 조사한다.
- `after appUdmaInit rc=0` 뒤 ETHFW에서 멈추면 ETHFW 제외 후보를 검토한다.
- `before cpu_sync` 이후 멈추면 참여 코어·동기화 메모리를 조사한다.
- trace가 여전히 잘리거나 비어 있으면 진단 가시성을 추가 확인한다. 마지막 부분만으로 원인을 확정하지 않는다.
- 코어 동기화·원격 서비스 초기화가 끝나고 MCU2_0 서비스가 등록됐을 때 수정된 04번을 실행한다. 실패 시 05는 보류한다.

```bash
sudo env RPMSG_LIB_DIR="$PWD/rpmsg-work/lib" \
 bash scripts/04-check-tidl-runtime.sh --init
# 출력에 나온 실제 로그 파일을 아래처럼 읽는다.
# sudo cat tidl-results/04-check-tidl-runtime.실제이름.log
```

## 5. 복구

SDK 원본으로 되돌리려면 [이전 가이드의 5번](deployment-trace-ko.md)의 `.pre-trace` 복구 명령을 그대로 사용한다. 그 링크는 이번 배치에서 변경하지 않았다. SSH가 안 되면 이전 가이드대로 실제 루트 SD를 호스트에 연결해 링크를 복구한다.

직전 진단판으로만 되돌리고 싶으면 보드에서 다음을 사용한다.

```bash
sudo ln -s bbai64-trace-mcu2-0/vx_app_rtos_linux_mcu2_0-trace.out \
 /lib/firmware/j7-main-r5f0_0-fw.return-trace
sudo mv -Tf /lib/firmware/j7-main-r5f0_0-fw.return-trace \
 /lib/firmware/j7-main-r5f0_0-fw
sync
sudo reboot
```

중간 링크가 이미 존재하면 위 명령을 반복하지 말고 상태를 확인한다. 모든 진단판은 보드 검증 전이며 정상 추론을 보장하지 않는다.
