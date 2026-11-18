# ETHFW 역할, 비활성화 영향 및 현재 시험 상태

## 결론

**ETHFW 비활성화 펌웨어는 이미 빌드·적용됐고 Step 04를 통과했다.** 2026-11-18 읽기 전용 SSH로 다시 확인한 링크는 `bbai64-noeth-mcu2-0/vx_app_rtos_linux_mcu2_0-noeth.out`, SHA256은 `567e257b39a2a6082c8a2394a3e49dea33b5add790449accae6d225f6bb5d695`다. 사용자 저장 trace에는 IPC 초기화 rc=0, 코어 동기화 및 원격 서비스 초기화 완료가 있다. [확인 자료](../../docs/bbai64-survey/ethfw-disabled-confirmation-20261118.log)

따라서 같은 펌웨어를 재빌드·재업로드할 필요는 없다. 보존된 배포 파일은 `firmware-work/deploy-noeth/`, [수동 적용·복구 가이드](../firmware-work/deployment-noeth-ko.md)가 있다. 기존 매니페스트의 board_verified=false는 패키징 시점의 상태이며, 이후 실기 결과는 이 문서 및 장애 분석 문서로 구분해 기록한다.

## ETHFW가 하는 일

ETHFW는 J721E의 MCU2_0에서 Ethernet 스위치 자원을 관리하고 다른 코어/OS에 네트워크 기능을 제공하는 TI Ethernet Firmware다. TIDL 연산 펌웨어 자체가 아니다. SDK 통합에서는 SoC Ethernet 드라이버·보드 포트 초기화, 가상 포트/MAC 주소 풀, 원격 설정 서버와 구성에 따른 시간 동기화·라우팅 예제를 포함한다.

근거: `sdk_original/vision_apps/utils/ethfw/src/app_ethfw_freertos.c`의 appEthFwInit, EthFwBoard_init, EthApp_initEthFw, appEthFwRemoteServerInit, MAC 주소 풀 주석(118행 부근), 가상 포트 설정(732행 부근), gPTP 조건부 초기화(629행 부근), interVLAN 구성(780/1057행 부근). 기능은 SDK 빌드 옵션·보드 배선에 따라 달라지며 모두 BBAI64에서 사용 중이었다는 뜻은 아니다.

## 비활성화 영향

| 기능 | noeth 후보에서의 영향 |
|---|---|
| MCU2_0 ETHFW 서버가 제공하는 CPSW 가상 스위치/MAC-only 포트와 원격 설정 | 해당 서버를 제공하지 않으므로 의존하는 Linux/QNX/RTOS 클라이언트는 사용 불가 |
| EVM GESI/QENET Ethernet 보드 초기화 | 이 ETHFW 경로는 실행하지 않음. 관련 EVM 확장 포트 지원을 제공하지 않음 |
| ETHFW에 포함된 lwIP 네트워크 앱·iperf 등 | 해당 펌웨어 경로의 서비스는 제공하지 않음. Debian의 별도 네트워크 앱과 구분 |
| ETHFW 기반 gPTP 시간 동기화, interVLAN/TSN 관련 데모 | 해당 ETHFW 구현에 의존하는 기능은 사용 불가. Linux의 모든 PTP/VLAN 기능을 비활성화한다는 뜻은 아님 |
| BBAI64 Linux eth0 및 SSH | 현재 eth0는 am65-cpsw-nuss 드라이버이며 noeth 적용 후 SSH로 접근 가능함을 확인. 모든 포트·부하·재부팅 조합을 검증한 것은 아님 |
| USB 네트워크 | 이번 빌드는 USB gadget 설정을 바꾸지 않음. 실제 연결 시험은 미수행 |
| TIOVX IPC, RPMsg 및 공유 메모리 | 유지. noeth에서 Step 04와 IPC 서비스 등록을 확인 |
| C71x/MMA TIDL 추론 | ETHFW는 목표 기능의 직접 구성요소가 아님. 다만 Step 05 실제 추론 성공은 아직 미확인 |
| 디스플레이·카메라 등 MCU 보드 의존성 | BUILD_MCU_BOARD_DEPENDENCIES=yes 유지. ETHFW를 껐다고 나머지 EVM 주변장치 의존성이 모두 사라지지는 않음 |

## 현재 수정 내용

- `BUILD_ENABLE_ETHFW=no`: MCU2_0의 ETHFW early/init/remote server 경로와 관련 링크 구성 제외.
- `BUILD_MCU_BOARD_DEPENDENCIES=yes`: 한 번에 여러 조건을 바꾸지 않도록 유지.
- 초기화 trace 및 R5F cache writeback 진단 패치 유지.
- SDK 버전, DT 메모리 맵, 커널, C71x/C66x/다른 R5F 파일은 이번 noeth 시험에서 변경하지 않음.

근거: `sdk_original/sdk_builder/vision_apps_build_flags.mak`, `vision_apps/platform/j721e/rtos/mcu2_0/concerto_mcu2_0_inc.mak`, `rtos/common/concerto.mak`, `rtos/common/app_init.c`의 ENABLE_ETHFW 조건부 코드 및 `firmware-work/deploy-noeth/build-manifest.json`.

## 다음 테스트를 막는 별도 문제

현재 Step 05는 **noeth 적용 이후에도 TIDL 세션 생성 중 timeout**이다. `before tidl_session` 다음 표식이 없고, local=ANY 요청에 sysfs src=-1, SDK 반환 endpt=0이 기록됐다. 커널 자동 주소 할당은 1024 이상이므로 이 반환 주소는 실제 주소와 다르다. ETHFW를 다시 끄는 작업으로 해결할 문제가 아니다.

다음 구현은 사용자 공간 RPMsg 호환 패치이며 아직 제작하지 않았다. 명시적 endpoint 예약·정확한 주소 반환·충돌 처리의 설계와 검증이 필요하다. 현재 파일 그대로 Step 05 반복을 권하지 않는다. 커널/펌웨어 재빌드는 요구되지 않는다. 이 보고서에서 새로운 RPMsg 바이너리가 준비된 것으로 표현하지 않는다. [장애 분석](rpmsg-failure-analysis-ko.md)

## 사용자 확인 사항

현재 사용 목적이 BBAI64 Linux 네트워크와 TIDL 추론이면 기존 noeth 시험 결과를 기준으로 계속 진행할 수 있다. 다른 코어에서 ETHFW 가상 포트, TSN/gPTP 데모, EVM 확장 Ethernet 포트를 사용할 계획이 있으면 해당 요구를 별도로 기록한다. 향후 이런 기능이 필요하면 BBAI64용 ETHFW 보드 지원을 별도 포팅해야 한다. 이미 보존한 .pre-noeth와 .pre-trace 복구 링크는 유지한다.
