# MAIN R5F0_0 진단 펌웨어 준비 및 빌드

현재 상태: **진단 패치와 빌드 보조 스크립트 준비 완료 / 전체 컴파일·링크 및 보드 실행 미검증**. SDK 원본과 보드는 변경하지 않았다.

## 왜 이 작업을 하는가

MAIN R5F0_0이 running이어도 IPC endpoint 13이 없으므로 앱 초기화 완료는 보장되지 않는다. UART를 사용할 수 없어 초기화 전후 표식을 IPC trace 버퍼에 직접 기록한다. ETHFW 초기화 이전/이후를 구분해 EVM 보드 초기화가 원인인지 판단하려는 작업이다.

SDK에는 `BUILD_MCU_BOARD_DEPENDENCIES=no`도 있다. `sdk_builder/vision_apps_build_flags.mak:242`는 비 EVM 보드나 HLOS가 주변장치를 제어할 때 이 설정을 권한다. 다만 처음부터 모든 옵션을 바꾸면 원인 구분이 어려우므로 다음 후보를 분리한다.

| 후보 | ETHFW | MCU 보드 의존성 | 용도 |
|---|---|---|---|
| trace | yes | yes | 기존 설정에 진단 표식만 추가. 먼저 시도 |
| noeth | no | yes | trace가 ETHFW 초기화 실패·대기를 가리킬 때 사용 |
| noboard | no | no | EVM 보드 초기화가 추가 장애일 때 검토. 영상·디스플레이 등 기능 범위가 달라짐 |

원격 stop/start나 자동 설치는 제공하지 않는다. 이 단계에서 바꾸는 대상은 MAIN R5F0_0 후보뿐이며 MCU R5F는 그대로 유지한다.

## 준비한 파일

- `0001-mcu2-0-init-trace.patch`: main/task 진입, OS, GTC, Sciclient, UDMA, 메모리, ETHFW, IPC, 코어 동기화, 원격 서비스 초기화의 전후 표식. 반환값이 있는 주요 초기화는 rc도 기록한다. 기존 ASSERT·초기화 순서는 유지한다.
- `modified/`: 패치 적용 결과 두 소스 파일. 직접 SDK 원본에 복사하지 않는다.
- `prepare.py`: 약 8 GiB SDK를 독립 복사하고 패치한다. 하드링크를 사용하지 않는다. 내부 절대 링크는 복사본으로 바꾸고 외부·깨진 링크는 기록한다.
- `build.sh`: MCU2_0만 선택하는 로컬 후보 빌드 명령. variant 간 객체 재사용을 막는다. 외부 파일을 가리키는 유효 심볼릭 링크가 있으면 빌드를 막는다.
- `source-SHA256SUMS`, `offline-validation.log`: 원본 소스 해시와 패치 적용 검사 결과.

## 소요 시간 및 현재 확인 범위

로컬 TI Arm Clang **4.0.4.LTS 실행 확인**, 패치 적용 및 결과 파일 일치, 스크립트 문법 검사를 통과했다. 전체 펌웨어 컴파일·링크는 수행하지 않았다. 따라서 아래 명령은 재현용 시작 절차이며 빌드 성공을 검증한 절차로 표현하지 않는다.

SDK 복사 자체가 약 8 GiB의 읽기·쓰기를 요구한다. 빌드는 사전 생성 라이브러리 유무에 따라 수분 또는 의존성 재빌드로 더 오래 걸릴 수 있다. 측정하지 않았으므로 완료 시간을 보장하지 않는다. 원본과 별개로 최소 15–20 GiB 여유 공간을 권장하며 후보마다 추가 공간이 필요하다. 이번 요청에 따라 긴 복사·전체 빌드는 시작하지 않았다.

## 호스트에서 실행할 순서

프로젝트 루트에서 실행한다. Linux x86_64 호스트의 Python 3, GNU make, patch가 필요하다. R5F 컴파일러는 SDK에 포함된 버전만 사용하며 ARM64 Linux용 GCC로 대체하지 않는다. Ubuntu 22.04 계열 SDK 호스트 환경을 우선하고 호스트 라이브러리 오류가 있으면 로그를 남기고 멈춘다. TI 저장소 다운로드나 설치 스크립트 실행은 필요하지 않다.

```bash
cd /home/corsair/Documents/sdk/ti_sdk_lab
command -v python3 make patch
sdk_original/ti-cgt-armllvm_4.0.4.LTS/bin/tiarmclang --version
hashes=$(realpath bbai64-porting/firmware-work/source-SHA256SUMS)
(cd sdk_original && sha256sum -c "$hashes")

# 이 명령부터 SDK 전체 복사가 진행된다. 목적지는 존재하지 않아야 한다.
python3 bbai64-porting/firmware-work/prepare.py \
  sdk_original bbai64-porting/firmware-work/sdk-trace

cat bbai64-porting/firmware-work/sdk-trace/bbai64-copy-links.txt

# 독립 복사본에서 빌드 명령 확인. make -n도 내부 메타파일을 만들 수 있다.
set -o pipefail
bash bbai64-porting/firmware-work/build.sh \
  bbai64-porting/firmware-work/sdk-trace trace dry-run \
  2>&1 | tee bbai64-porting/firmware-work/trace-dry-run.log

# dry-run에 오류가 없을 때만 실행. 포그라운드 빌드이며 보드에는 접근하지 않는다.
JOBS=2 bash bbai64-porting/firmware-work/build.sh \
  bbai64-porting/firmware-work/sdk-trace trace build \
  2>&1 | tee bbai64-porting/firmware-work/trace-build.log
```

다른 호스트에서는 첫 cd만 실제 프로젝트 위치로 바꾼다. `noeth` 후보는 새로운 목적지 `sdk-noeth`를 prepare.py로 만들고 build.sh의 경로와 variant를 각각 `sdk-noeth noeth`로 바꾼다. noboard도 같은 방식이다. 다른 variant의 out/lib/obj를 복사해 재사용하지 않는다.

**중단 조건:** 원본 해시 불일치, 외부 링크, compiler 실행 실패, missing header/archive, No rule to make target, 링크 실패. `build.sh`는 전체 `make sdk`로 자동 확장하지 않는다. 이미 제공된 PDK·app_utils·TIOVX 등의 라이브러리로 링크되지 않으면 해당 로그를 먼저 검토해야 한다. sdk 전체 재빌드나 임의 라이브러리 대체를 진행하지 않는다. 명령의 `-B`는 변경된 공통 라이브러리와 실행파일을 다시 생성하기 위한 것이며 실제 대상 의존성에 따라 빌드량이 늘어날 수 있다.

## 빌드 후 오프라인 확인

출력 후보는 다음에서 찾는다. SDK 구성에 따라 최종 디렉터리 이름이 다를 수 있으므로 find 결과를 확인한다.

```bash
find bbai64-porting/firmware-work/sdk-trace/vision_apps/out \
  -name 'vx_app_rtos_linux_mcu2_0.out' -type f -print
```

빌드가 성공해도 바로 설치하지 않는다. 결과 ELF와 링크 map을 기존 `staging/firmware/vision_apps_evm/vx_app_rtos_linux_mcu2_0.out` 및 적용된 DT 예약 영역과 대조한다. LOAD 세그먼트가 MCU2_0 예약 영역 안에 있는지, resource table/trace 주소와 크기가 적절한지, 다른 코어 영역과 겹치지 않는지 확인한다. 빌드 로그에서 CPU_mcu2_0, FREERTOS, release 및 선택한 ENABLE_ETHFW 설정도 확인한다. 이 확인 전의 출력은 **배포 승인 전 후보**다. GP/HS 서명 방식은 기존 보드에서 사용한 방식과 같아야 하며 임의로 전환하지 않는다.

## 이후 사용자 수동 적용 시험

메모리 맵 검토를 통과한 뒤 별도 배포 명령을 확정한다. 현재 가이드는 검토되지 않은 ELF를 설치하는 명령을 제공하지 않는다. 기존 정상 부팅 펌웨어는 보존하고 후보 하나만 적용하며, SSH가 끊어질 때 SD를 다른 컴퓨터에서 수정할 수 있어야 한다. UART가 없으므로 복구할 SD 접근이 없다면 시험 적용을 보류한다.

재부팅 후 `remoteproc5/name`이 여전히 5c00000.r5f인지 확인하고 trace0 및 RPMsg 목록을 읽는다. `BBAI64:` 표식 중 마지막 before/after 쌍으로 원인을 좁힌다.

- ETHFW before만 남거나 after의 rc가 실패: noeth 후보의 근거.
- IPC 전 단계에서 정지: 해당 초기화의 자원·보드 의존성을 먼저 조사.
- cpu_sync before만 남음: 참여 코어 목록과 공유 로그/동기화 메모리 확인.
- remote_service까지 통과: endpoint 13/21 등록을 확인하고 Step 04 수행.
- 표식이 전혀 없음: main 이전, 실행 이미지, trace 주소·캐시 가시성을 추가 확인. trace 부재만으로 실행 불가를 확정하지 않는다.

진단 함수는 SDK의 기존 Ipc_Trace_printf를 사용한다. 해당 구현 자체의 캐시 가시성을 보장하는 수정은 포함하지 않았다. TRACE는 미검증 진단 수단이며 정상 동작을 보증하는 장치가 아니다. Step 04가 IPC 오류 없이 통과한 뒤에만 Step 05를 수행한다.


## trace 후보 빌드 후 검사 및 적용

사용자 빌드 결과 ELF와 map을 확인했다. DDR LOAD 영역, 세그먼트 중복, resource table 일치, trace 배치와 진단 문자열 검사를 통과했다. `firmware-work/deploy-trace/`에 배포 후보 세트를 준비했다. 보드 동작은 미검증이며 사용자 수동 적용·복구 절차는 [적용 가이드](deployment-trace-ko.md)에 있다.


## 캐시 반영 진단판 준비 완료

0002 패치로 R5F trace 기록 후 변경 영역을 CSL 캐시 clean과 DSB로 반영한다. 로컬 MCU2_0 빌드·링크, ARM 호출 확인, 기록 범위 모의 검사 및 ELF 메모리 검증을 통과했다. 새 세트는 `deploy-trace-wb/`, 수동 업로드·복구 절차는 [새 가이드](deployment-trace-wb-ko.md)에 있다. 보드 미적용·동작 미검증이며 원인 확정 전 진단 단계다.


## noeth 후보 준비 완료

독립 sdk-noeth 복사본에 진단·캐시 패치를 적용하고 ETHFW=no, MCU_BOARD_DEPENDENCIES=yes로 로컬 MCU2_0 빌드·링크를 완료했다. peer 설정은 유지된다. trace 내부 주소 재배치 외 resource table 차이가 없고 DDR 범위·중복·진단/캐시 호출·ETHFW 제거 검사를 통과했다. 배포 후보는 deploy-noeth/, [사용자 업로드·적용·복구 가이드](deployment-noeth-ko.md)를 제공한다. 커널 빌드와 보드 업로드·변경은 수행하지 않았다. 보드 동작은 미검증이다.
