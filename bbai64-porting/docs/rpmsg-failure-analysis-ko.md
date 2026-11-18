# Step 04 IPC 실패 분석 및 대응 계획 — 2026-11-18

## 결론

**확인됨:** 실패 지점은 MCU2_0(MAIN R5F0_0, 5c00000.r5f)의 Vision Apps IPC endpoint 13 부재다. running은 Linux remoteproc의 기동 상태이며 RTOS 앱 초기화 완료를 보증하지 않는다. 원인은 아직 특정하지 못했다. 현재는 추가 커널·DT 변경보다 R5F 앱 초기화 위치를 확인하는 것이 우선이다.

## 추가 조사 결과

읽기 전용 SSH에서 uname, 각 remoteproc name/state/firmware, RPMsg sysfs 목록, 펌웨어 링크·SHA256 및 dmesg를 수집했다. [원본 결과](../../docs/bbai64-survey/rpmsg-followup-20261118.log). 관리자 명령, endpoint 생성, remoteproc 조작, 파일 업로드는 수행하지 않았다.

- **확인됨:** 실행 커널은 tidl2이고 C66x 두 개, C71x, MAIN R5F 두 개는 running이다. MCU R5F는 attached 상태를 유지한다.
- **확인됨:** MAIN R5F0_0의 virtio5에는 ctrl/ns만 있고 port 13 서비스가 없다. 다른 Vision Apps 코어 네 개에는 port 13이 있다. 모든 Vision Apps 코어에서 port 21은 관측되지 않는다.
- **확인됨:** /lib/firmware/j7-main-r5f0_0-fw는 bbai64-psdk-11.02/vx_app_rtos_linux_mcu2_0.out을 가리킨다. 파일 SHA256은 준비한 SDK 파일과 일치한다: `6f99b5497f75be958d59d845d782b0ffa1503eb22c75b9b4f895d641b61ea1c2`. 실행 중 메모리 내용 자체를 검증한 것은 아니다.
- **확인됨:** 사용자가 읽은 trace0는 출력이 없다. debugfs의 ls 크기 0은 실제 버퍼 길이를 의미하지 않는다.
- **확인됨:** SDK `vision_apps/platform/j721e/rtos/ipc_trace.c`는 Ipc_Trace_printf 전용 버퍼를 사용한다. `rtos/common/app_init.c`의 appLogWrInit은 별도의 g_app_log_shared_mem을 사용한다. 따라서 일반 앱 로그가 빈 trace0에 반드시 나와야 한다는 전제는 성립하지 않는다.

## 원인 후보와 증거의 한계

**가능성 높음:** MAIN R5F0_0 앱이 IPC 서비스 등록 전 단계에서 멈추거나 오류 처리에 들어갔을 가능성. 해당 코어의 서비스만 없고 나머지 코어의 port 21도 없는 현상은 초기화·코어 동기화 미완료와 양립한다. SDK app_init.c는 appIpcInit 후 MCU2_0을 master로 appLogCpuSyncInit을 실행하고 그 뒤 appRemoteServiceInit을 실행한다. port 21 부재만으로 모든 코어의 별도 고장을 단정하지 않는다.

**우선 조사 후보, 미확인:** EVM용 ETHFW 및 보드 초기화. SDK app_init.c는 appMemInit 뒤 appEthFwInit을 호출하고 그 후 appIpcInit을 호출한다. `vision_apps/utils/ethfw/src/app_ethfw_freertos.c`는 J721E에서 GESI 보드 플래그를 설정하고 EthFwBoard_init을 실행한다. 실제 배포 ELF에도 ETHFW 초기화와 GESI EEPROM 오류 문자열이 존재한다. BBAI64에서 EVM 보드 초기화가 적합하다고 볼 수 없다. 다만 현재 자료로 정확히 그 함수에서 멈췄다고 확정할 수는 없다. Sciclient, UDMA, MPU 검사 및 더 이른 초기화 오류도 후보로 남는다.

RPMsg 0.6.11 적용 후 local endpoint 조회 실패는 경고로 바뀌었다. endpoint=0 fallback의 실제 왕복 호환성은 별도 미검증이다. 이는 누락된 R5F 서비스 자체를 생성하지 않으며 현재 직접 실패 원인과 구분해야 한다.

## 권장 작업 순서와 중단 기준

1. **로컬에서 진단용 MAIN R5F0_0 펌웨어 수정안을 준비한다.** SDK 원본과 분리된 소스에서 Sciclient/UDMA/메모리/ETHFW/IPC 초기화 전후에 명시적인 Ipc_Trace_printf 표식을 추가한다. UART 대신 trace0로 마지막 도달 지점을 판별하는 것이 목적이다. 오류 반환도 trace로 기록하고 메모리 맵·resource table은 유지한다. 현재 보고서는 수정안의 설계이며 아직 진단 펌웨어를 제작하거나 적용하지 않았다.
2. **ETHFW 비활성화 후보를 검토한다.** BUILD_ENABLE_ETHFW=no가 MCU2_0의 ENABLE_ETHFW 및 관련 링크 구성을 실제로 제거하는지 전체 빌드 인자를 확인한다. 먼저 동일 SDK 버전과 메모리 맵을 유지한 MAIN R5F0_0용 후보를 준비한다. UART·pinmux·EVM 주변장치 초기화도 별도로 검토한다. ETHFW를 끄면 원인이 해결된다고 보장하지 않는다.
3. **사용자 검토 후 펌웨어 한 개만 수동 시험한다.** 기존 파일은 보존하고 별도 이름으로 배치한다. 원격에서 임의 stop/start하지 않는다. 네트워크 유지 및 SD 복구 조건을 확보하고 사용자가 적용·재부팅한다. MCU R5F 펌웨어는 변경하지 않는다.
4. **합격 기준:** MAIN R5F0_0의 endpoint 13 등록, 참여 코어 동기화 완료 및 필요한 endpoint 21 등록, 수정된 Step 04의 IPC 오류 없는 통과. 실패하면 trace의 마지막 표식으로 해당 초기화 경로만 보완한다.
5. **그 뒤 Step 05:** 동일 RPMsg 라이브러리를 지정해 원격 노드 생성·반환과 CPU 대비 출력을 검증한다. 이 단계 전에는 모델 재양자화나 전체 커널 재빌드를 반복할 이유가 없다. endpoint=0으로 반환 메시지가 실패하면 그때 동적 host endpoint 전달 방식을 조사한다.

지금 사용자에게 반복 실행을 요청할 추가 명령은 없다. 현재 확보한 trace가 비어 있으므로 같은 cat/Step 04 반복은 새 근거를 주지 않는다. 다음 실질 작업은 진단 펌웨어 및 ETHFW 제외 빌드 구성의 로컬 준비다.


## 후속 준비 완료

진단 표식 패치, 독립 SDK 복사 도구, MCU2_0 후보별 빌드 스크립트 및 [호스트 빌드 가이드](../firmware-work/README-ko.md)를 준비했다. 패치 적용·결과 일치와 스크립트 문법은 확인했다. 전체 SDK 복사 및 펌웨어 컴파일·링크는 긴 작업 가능성이 있어 시작하지 않았다. 배포 ELF는 아직 없다.


## trace 후보 빌드 후 검사 및 적용

사용자 빌드 결과 ELF와 map을 확인했다. DDR LOAD 영역, 세그먼트 중복, resource table 일치, trace 배치와 진단 문자열 검사를 통과했다. `firmware-work/deploy-trace/`에 배포 후보 세트를 준비했다. 보드 동작은 미검증이며 사용자 수동 적용·복구 절차는 [적용 가이드](../firmware-work/deployment-trace-ko.md)에 있다.


## 진단 펌웨어 적용 후 결과 — 2026-11-18

사용자가 제공한 `04-check-tidl-runtime.PjzpRS.log`에서 DMA heap 초기화는 성공했으나 MCU2_0 endpoint 13 및 참여 코어 endpoint 21 부재가 계속된다. 새로운 커널·모델 문제를 가리키는 증거는 없다. 새 펌웨어는 원인 관측용이며 이 결과 자체는 수정 실패를 의미하지 않는다.

읽기 전용 SSH 수집 결과는 `docs/bbai64-survey/trace-firmware-result-20261118.log`에 저장했다. 새 파일 링크·SHA256이 배포 후보와 일치하고 dmesg에서 12933488 바이트 이미지 로드를 확인했다. 따라서 단순 배치 누락 가능성은 낮다. 수집된 trace는 352바이트이며 아래까지 확인된다.

```
BBAI64: after appLogGlobalTimeInit rc=0
BBAI64: before appSciclientInit
BBAI64: after appSciclientInit rc=0
BBAI64: bef
```

**확인됨:** main, OS task, GTC, Sciclient 초기화까지 도달했다. 완전한 다음 표식은 보이지 않는다. 코드 순서상 다음 표식은 before appUdmaInit이다.

**미확인:** UDMA 정지인지 그 이후 단계 정지인지. 352바이트는 32바이트 경계이며 표식 중간에서 끝난다. SDK `j721e_mpu_cfg.c` region 6은 DDR을 WB/WA cacheable로 설정한다. trace 주소 0xa342bc00은 비캐시 IPC 영역 [0xa2000000,0xa2100000) 밖이다. SDK `ipc_trace.c`의 Ipc_Trace_printf는 버퍼 저장 뒤 cache writeback을 하지 않는다. 그러므로 관측된 마지막 문자와 실제 실행 위치가 다를 수 있다. 기존 진단 패치에는 이 가시성 보완이 없었다. 이 근거만으로 ETHFW 또는 UDMA를 확정해서는 안 된다.

### 다음 대응

1. 진단 trace의 캐시 가시성을 먼저 보완한다. RTOS task 실행 이후 표식마다 해당 trace 버퍼의 변경 영역을 SDK의 R5F cache writeback API로 반영하는 방식을 검토한다. main/OS 이전에는 OSAL API 호출 가능 조건을 별도로 확인한다. MPU 전체 변경 또는 광범위한 캐시 비활성화는 우선하지 않는다.
2. trace 초기화·반영 보완 후보를 로컬 빌드·메모리 검증한 뒤 사용자가 교체한다. 현재 보고서 시점에는 추가 패치/ELF를 만들지 않았다. 이후 정상적으로 끝나는 before/after와 rc로 UDMA, ETHFW, IPC 중 장애 구간을 결정한다.
3. ETHFW에서 정지한 것이 확인될 때 noeth 후보를 사용한다. 현재 noeth로 원인이 확정됐다는 판단은 보류한다. Step 05와 모델 재컴파일은 계속 보류한다.

사용자가 이번 로그·trace의 관리자 읽기를 승인했으나 `sudo -n cat`은 암호 요구로 실행되지 않았다. 인증 설정 변경이나 암호 수집은 하지 않았다. 이후 사용자가 상세 로그를 직접 제공하여 위 판단에 반영했다. 원격 시스템 변경은 수행하지 않았다.


## 캐시 반영 진단판 준비 완료

0002 패치로 R5F trace 기록 후 변경 영역을 CSL 캐시 clean과 DSB로 반영한다. 로컬 MCU2_0 빌드·링크, ARM 호출 확인, 기록 범위 모의 검사 및 ELF 메모리 검증을 통과했다. 새 세트는 `deploy-trace-wb/`, 수동 업로드·복구 절차는 [새 가이드](../firmware-work/deployment-trace-wb-ko.md)에 있다. 보드 미적용·동작 미검증이며 원인 확정 전 진단 단계다.


## 캐시 반영 진단판 실기 결과 — ETHFW 구간으로 범위 축소

사용자가 수집한 `tidl-results/trace-wb/`를 읽기 전용 SSH로 읽고 `docs/bbai64-survey/trace-wb-result-20261118.log`에 저장했다. 보드의 펌웨어 링크와 SHA256은 새 캐시 반영 후보와 일치한다.

```
BBAI64: after appSciclientInit rc=0
BBAI64: before appUdmaInit
BBAI64: after appUdmaInit rc=0
BBAI64: before appMemInit
BBAI64: after appMemInit rc=0
BBAI64: before appEthFwInit
```

**확인됨:** Sciclient, UDMA, 메모리 초기화는 성공 반환했다. appEthFwInit에 진입하기 직전까지 실행됐으며 이후 반환 표식과 appIpcInit 진입 표식은 없다. MCU2_0 endpoint 13은 계속 없고 다른 참여 코어의 endpoint 13은 존재한다. ETHFW early 초기화와 OS 기동은 이미 통과했다.

**가능성 높음:** appEthFwInit 내부에서 대기·오류 정지·예외가 발생해 IPC 초기화까지 도달하지 못했다. 기록 가시성을 보완한 완전한 표식이므로 이전 잘린 trace보다 강한 근거다. 단, ETHFW 내부의 정확한 함수와 오류 종류는 아직 미확인이다. EVM용 GESI/보드 초기화 부적합은 후보이며 확정하지 않는다. Linux remoteproc의 running은 이 상태를 탐지하지 못할 수 있다.

### 다음 권장안

동일 SDK·메모리 맵·참여 코어 구성을 유지하면서 MCU2_0에 `BUILD_ENABLE_ETHFW=no`, `BUILD_MCU_BOARD_DEPENDENCIES=yes`인 noeth 후보를 만들고 진단 표식·cache writeback을 유지한다. CPU 목록은 기존 런타임 설정과 동일하게 유지한다. EVM 영상·디스플레이 초기화까지 한꺼번에 끄는 noboard 후보는 이 단계의 기본안이 아니다. 변경 범위를 ETHFW 제외로 제한해 원인과 효과를 분리한다.

noeth 재부팅 후에는 appEthFwInit 표식이 없어야 하고 `after appIpcInit rc=0`, 코어 동기화 전후, 원격 서비스 초기화 전후와 endpoint 13/21을 확인한다. 이후 초기화에서 다시 정지하면 해당 마지막 표식으로 다음 범위를 좁힌다. 04가 IPC 오류 없이 통과한 뒤에만 05로 넘어간다. noeth로 정상 통신이 되면 ETHFW 초기화 경로가 이 단계의 장애라는 근거가 강화되지만, 구체적인 GESI 함수까지 확정되는 것은 아니다.

ETHFW가 제공하는 MCU2_0 CPSW 가상 Ethernet 기능은 비활성화된다. 현재 SSH용 Linux 네트워크와의 연관성을 적용 전 확인하고 SD 복구를 확보한다. Linux 네트워크 장치 전체가 영향 없다고 보장하지 않는다. 이 분석 단계에서는 새 noeth 펌웨어 빌드·업로드·원격 상태 변경을 수행하지 않았다.


## noeth 후보 준비 완료

독립 sdk-noeth 복사본에 진단·캐시 패치를 적용하고 ETHFW=no, MCU_BOARD_DEPENDENCIES=yes로 로컬 MCU2_0 빌드·링크를 완료했다. peer 설정은 유지된다. trace 내부 주소 재배치 외 resource table 차이가 없고 DDR 범위·중복·진단/캐시 호출·ETHFW 제거 검사를 통과했다. 배포 후보는 deploy-noeth/, [사용자 업로드·적용·복구 가이드](../firmware-work/deployment-noeth-ko.md)를 제공한다. 커널 빌드와 보드 업로드·변경은 수행하지 않았다. 보드 동작은 미검증이다.

## noeth 실기 성공 및 Step 05 진행 조건

사용자가 Step 04 성공(`04-check-tidl-runtime.4ilLBl.log`)을 보고했다. 일반 사용자 SSH로 저장된 noeth trace와 현재 RPMsg 목록·펌웨어 해시·모델 파일을 확인했다. 원본은 `docs/bbai64-survey/noeth-success-20261118.log`다. root 전용 Step 04 상세 로그는 이번 조회에 포함하지 않았다.

**확인됨:** noeth 해시 일치, appIpcInit rc=0, cpu_sync 및 remote_service의 after 표식이 있다. C71x, C66x 두 개, MAIN R5F 두 개에서 port 13/21 서비스가 등록됐다. ETHFW 제외로 이전 초기화 장애를 회피했고 Step 05 진행 조건을 충족했다. ETHFW 내부의 정확한 문제 함수 및 C71x/MMA 실제 추론 성공은 여전히 미확인이다.

다음 사용자 수동 명령:

```bash
cd ~/bbai64-porting
sudo env RPMSG_LIB_DIR="$PWD/rpmsg-work/lib" \
 bash scripts/05-check-onnx-ep.sh \
 "$HOME/models/resnet18/model.onnx" \
 "$HOME/models/resnet18/artifacts/" \
 "$HOME/models/resnet18/input.f32" 1.0
```

1.0은 준비된 양자화 모델의 기능 확인용 절대 오차 허용값이다. 모델 정확도 승인 기준으로 사용하지 않는다. 모델·아티팩트·입력이 보드에 존재함을 확인했고 input.f32 크기는 기대값 602112바이트다. 이번에는 해시 전체 재검증은 하지 않았다.

TIDL_BENCHMARK_OK 및 원격 subgraph 처리 구간이 있으면 CPU 대비 출력·TIDL 실행 경로 검사를 통과한 것이다. 스크립트는 MMA 증거 확인을 남겨 미검증으로 표시하도록 설계되어 있다. 미검증 요약만 보고 실패로 오해하지 말고 상세 로그를 확인한다. 최종 가속 검증에는 같은 실행의 C71x 펌웨어 프로파일·MMA 사용 근거를 추가 대조한다. timeout/원격 노드 생성/수치 비교 오류이면 반복하지 말고 상세 로그로 범위를 좁힌다. 보드에서 추론 실행은 사용자가 수행한다.

## Step 05 중단 로그 분석

사용자 첨부 로그는 `05-check-onnx-ep.JEIEur.log`, 실행 요약의 로그는 `05-check-onnx-ep.5cKoUM.log`이므로 두 실행을 동일하다고 단정하지 않는다. 첨부 원문은 `docs/bbai64-survey/step05-JEIEur-user.log`에 보존했다.

**확인됨:** 첨부 실행에서 49/49 노드가 하나의 TIDL subgraph로 배정됐고 DMA heap·IPC·호스트 TIOVX 초기화가 완료됐다. `TIDL_BENCHMARK_OK`, 출력 오차 결과, 원격 추론 완료 근거는 없다. unused initializer 경고는 모델 로딩 중 불필요한 초기값 제거 메시지이며 이 로그에서 직접 실패를 뜻하지 않는다. signal 15 종료는 SIGTERM이고 스크립트의 timeout 120s와 양립하지만, 종료 원인을 로그만으로 확정하지 않는다. 사용자가 제시한 별도 실행의 Ctrl-C도 구분한다. 현재 probe는 세션 생성과 Run 전후 표식이 없어 정확한 대기 API를 특정할 수 없다. stdout 버퍼링 때문에 출력 순서도 실제 실행 순서와 완전히 같다고 보장할 수 없다.

**가능성 높음인 원인 후보:** RPMsg 0.6.11의 endpoint=0 fallback과 TIOVX의 응답 포트 전달 불일치. `rpmsg-work/source/src/rpmsg_char.c`는 local endpoint 조회 결과가 음수면 0을 반환한다. `app_utils/utils/ipc/src/app_ipc_linux_rpmsg_char.c:381`은 이를 local_endpt로 저장하고 `tiovx/source/platform/board/common/tivx_ipc.c:281`의 ownIpcGetHostPortId가 그 값을 사용한다. `tiovx/source/framework/vx_obj_desc.c`는 host_port_id를 공유 descriptor와 IPC 전송에 사용한다. 따라서 단순 endpoint open이 성공한 것만으로 반환 경로가 맞다고 볼 수 없다. root-only 상세 로그를 추가 관리자 읽기로 수집하지는 않았다.

읽기 전용 SSH에서 중단 후 ort-probe/검사 timeout 프로세스는 관측되지 않았다. RPMsg 기본 endpoint의 src는 1024, 서비스 21에서는 1025 등이 보였다. 결과는 `docs/bbai64-survey/step05-endpoint-check-20261118.log`. 이는 기본 endpoint 속성이 존재함을 확인한 것이며 실행 중 새로 만든 endpoint의 실제 주소를 측정한 것은 아니다. 이전의 경고를 일률적으로 sysfs 속성 부재로 해석한 설명은 좁혀야 한다. 동적으로 생성된 endpoint의 src가 RPMSG_ADDR_ANY(-1)로 남아 조회 결과가 음수가 되는 경우도 확인 대상이다. 현 커널 rpmsg_char.c의 src_show는 chinfo.src를 노출하고 open은 별도 rpmsg_create_ept를 호출하므로 실제 할당 주소와 요청값의 차이를 확인해야 한다.

### 다음 최소 작업

1. 사용자가 최신 5cKoUM 상세 로그를 제공해 실행 차이를 확인한다. 05 반복, 모델 재양자화 및 커널·DT·펌웨어 변경은 보류한다.
2. 로컬 probe에 CPU/TIDL session 생성·CPU Run·TIDL Run·benchmark 전후 즉시 출력 표식을 추가하고 timeout과 Ctrl-C 종료를 구별하도록 스크립트 판정을 보완한다. SDK CPU/TIDL 함수의 정확한 대기 지점을 확정한다.
3. RPMsg 라이브러리에 요청 주소·sysfs src·반환 endpt를 기록하는 진단을 준비한다. 필요하면 커널이 충돌 검증하는 명시적 local endpoint 할당과 정확한 주소 반환 방식을 사용자 공간에서 검토한다. 단순히 0을 임의의 상수로 바꾸는 것은 피한다. 실패 시 적절히 종료하고 동시 프로세스 주소 충돌도 고려한다.
4. 실제 응답 포트가 잘못 전달된 것이 확인되면 사용자 공간 호환 패치를 우선한다. 올바른 응답 포트에서도 멈추면 그때 C71x 타깃 초기화·공유 descriptor/캐시·펌웨어 로그로 범위를 넓힌다.

이 절은 진단 결과 및 다음 작업 계획이며 probe/라이브러리의 추가 수정·업로드·보드 실행은 아직 수행하지 않았다.

### 5cKoUM 상세 로그 추가 확인

사용자가 해당 실행의 상세 로그를 제공했다. 원문은 `docs/bbai64-survey/step05-5cKoUM-user.log`에 저장했다. JEIEur와 동일하게 49/49 노드 위임, DMA heap·IPC·호스트 초기화 성공, local endpoint=0 경고 10회, signal 15 종료이며 추론 완료·수치 비교·benchmark 결과는 없다. 반복 실행에서도 같은 관측 패턴이므로 단발 모델 파싱 오류를 가리키는 근거는 없다. endpoint 응답 주소 불일치는 우선 진단 후보를 유지하지만 아직 원인 확정은 아니다. SIGTERM의 발신자·정확한 대기 API·실제 local endpoint 값은 로그만으로 확정할 수 없다. 다음은 세션/Run 전후 즉시 출력과 RPMsg 주소 진단을 추가하는 사용자 공간 수정이다. 커널·DT·펌웨어 재빌드 없이 준비할 수 있으며 적용은 사용자 수동 방식으로 유지한다. 이 시점 추가 코드 수정 및 보드 실행은 수행하지 않았다.

## Step 05 사용자 공간 진단판 준비 완료

probe의 세션·Run·benchmark 전후 즉시 출력, RPMsg 요청/조회/반환 주소 기록, timeout·SIGINT 종료 구분을 구현했다. 기존 주소 처리 동작은 유지한다. ARM64 공유 라이브러리 빌드와 공개 심볼 일치, shell 문법 및 호스트 probe 문법 검사를 통과했다. ARM64 probe 링크·보드 실행은 미검증이다. [사용자 업로드·시험 가이드](../rpmsg-work/step05-diagnostics-ko.md)와 step05-diagnostics.tar.gz를 제공한다. 보드 업로드·실행은 수행하지 않았다.

## bvJdkv 진단 결과 — TIDL 세션 생성 대기 및 local endpoint 반환 오류 확인

사용자 제공 로그를 `docs/bbai64-survey/step05-bvJdkv-user.log`에 보존했다.

**확인됨:** CPU session은 549ms 이내 완료됐다. 마지막 PROBE_STAGE는 `before tidl_session`이며 `after tidl_session`은 없다. 따라서 Ort::Session(target) 생성 내부에서 120초 제한을 초과했다. CPU Run/TIDL Run 및 출력 비교는 호출되지 않았다. wrapper exit_code=124이므로 이번 실행은 timeout으로 분류된다.

**확인됨:** 열 개의 요청이 local=4294967295(ANY)이고 생성 endpoint의 sysfs src 원문은 -1이다. 라이브러리는 이를 조회 실패로 처리해 0을 SDK에 반환했다. 속성 파일이 없던 것이 아니라 요청값 ANY가 노출된 사례다. 현재 커널 `drivers/rpmsg/virtio_rpmsg_bus.c`는 ANY 요청에 id_min=1024부터 idr_alloc을 수행한다. 따라서 실제 할당 주소가 0일 수 없는데 라이브러리는 0을 반환한다. 실제 개별 할당 주소 숫자를 로그에서 측정한 것은 아니다.

SDK app_ipc_linux_rpmsg_char.c의 local_endpt 저장, tivx_ipc.c의 ownIpcGetHostPortId, vx_obj_desc.c의 공유 descriptor host_port_id 전달을 연결하면 **잘못된 응답 포트 전달 결함은 확인됐고 이번 세션 생성 대기의 유력 원인**이다. 이 결함만 고치면 전체 추론이 성공한다는 것은 미검증이다.

SIGTERM 뒤 중복 cleanup 및 invalid handle 오류는 종료 과정에서 발생했다. 대기 이전의 직접 원인으로 간주하지 않는다. 별도 라이브러리 핸들/종료 재진입 문제 가능성은 남지만 우선 응답 포트 결함을 해결한다.

### 다음 구현 방향

커널 변경 없이 사용자 공간 호환 패치를 우선한다. ANY 요청을 라이브러리에서 명시적 local 주소로 바꾸어 커널에 예약하게 하고, 성공한 주소를 SDK에 정확히 반환하는 후보를 검토한다. TIOVX uint16 host_port_id 범위, reserved 주소, 서로 다른 프로세스/같은 rproc의 충돌, endpoint 생성이 아니라 open 시 실제 예약되는 커널 동작, 실패 정리·재시도 범위를 반영해야 한다. 단순히 0을 1024로 바꾸거나 PID 기반 주소가 충돌하지 않는다고 가정해서는 안 된다. 지원 불가·불일치는 명확히 실패시키고 0 fallback을 사용하지 않는다.

로컬 패치·ARM64 빌드·오프라인 검증 및 사용자 수동 시험 가이드를 다음 작업으로 준비한다. 보드에서 유효 주소 요청=조회=반환, after tidl_session, after tidl_run, TIDL_BENCHMARK_OK 순서로 확인한다. 이번 로그 분석 시점에는 해당 호환 패치를 아직 작성하지 않았다. 커널·DT·펌웨어·모델 변경 및 보드 재실행은 수행하지 않았다.

## ETHFW 비활성화 재요청에 대한 상태 확인

읽기 전용 SSH로 현재 noeth 링크/해시와 저장된 성공 trace를 재확인했다. 동일 기능의 펌웨어를 다시 빌드·업로드하지 않았다. 역할과 제한은 [ETHFW 영향 보고서](ethfw-role-and-disable-ko.md)에 정리했다. 최신 Step 05의 local endpoint 반환 결함은 별도 사용자 공간 문제이며 noeth 재적용으로 해결된다고 표현하지 않는다.

## 호환 패치 구현 선택 확정 — tidl3 빌드 직전

사용자 공간 명시 주소 예약 우회안을 검토한 결과, endpoint 예약이 open에서 이루어지고 실패 시 생성 cdev 정리가 복잡해지는 점을 고려해 실제 주소를 이미 가진 커널 src_show를 최소 수정하는 방식으로 변경했다. 이전의 사용자 공간 우선 계획은 이 절로 대체한다. OS 루트파일시스템 재생성은 필요 없으며 사용자가 새 커널·일치 모듈 세트를 빌드한다.

0004 패치는 열린 endpoint의 ept->addr를 ept_lock 안에서 읽어 src로 노출하고 열리지 않은 경우 요청값을 유지한다. 커널 자동 충돌 처리를 그대로 사용한다. 기본 소스에 패치 적용·결과 일치, 기존 DMA 패치 합성 결과 일치, diff 검사·스크립트 문법을 확인했다. out-tidl3/.config 준비 완료, 컴파일·링크·새 바이너리·보드 변경은 미수행이다. [빌드 가이드](../patches/tidl3-build-start-ko.md) 및 scripts/build-tidl3-kernel.sh를 제공한다. 기존 noeth 펌웨어와 diagnostic-lib를 유지하고 새 커널에서 응답 주소 및 TIDL 세션/실행을 검증할 계획이다. 전체 추론 해결 여부는 미검증이다.

## tidl3 사용자 빌드 완료 및 배포 검토

사용자 빌드의 최종 modules_install/depmod/패키징 완료, 전체 staging checksum, rpmsg_char vermagic tidl3를 확인했다. cc33xx debugfs의 FORTIFY 경고 한 건은 미해결로 기록한다. 읽기 전용 SSH로 기존 tidl2 부트 설정·여유 공간·noeth 해시를 확인했다. [사용자 수동 배포 가이드](tidl3-deployment-ko.md)에 새 커널/일치 모듈 설치, 별도 기본 부트 항목, tidl2 복원, 04/05 검증 절차를 정리했다. Codex는 커널 빌드·업로드·보드 변경을 수행하지 않았다.

## tidl3 적용 후 SmOQ5M — 응답 주소 해결, Run 단계로 장애 이동

원문은 `docs/bbai64-survey/step05-SmOQ5M-user.log`. 사용자 보고 04 성공과 05 상세 로그를 대조했다.

**확인됨:** IPC endpoint의 sysfs raw=1026/반환 endpt=1026, 원격 서비스 endpoint의 raw=1027/반환 endpt=1027이다. 기존 raw=-1/반환0 문제가 사라졌다. 서로 다른 rproc의 endpoint 번호가 같아도 할당 범위가 각 virtio 장치별이므로 그 자체로 충돌이 아니다.

**확인됨:** after tidl_session(2689ms), after cpu_run(2934ms)이 있고 before tidl_run 이후 반환이 없다. exit_code=124로 120초 제한 종료다. 이전 세션 생성 단계 timeout과 달리 TIDL 세션 생성 및 CPU 추론까지 통과했다. 응답 주소 수정은 관측 가능한 효과가 있지만 전체 가속 추론의 충분조건은 아니다. 모델 오차 비교나 benchmark 조회는 실행되지 않았다.

**미확인:** target.Run 내부에서 멈춘 정확한 위치. EP의 첫 Run에는 원격 노드 생성·graph verify 등 지연 초기화가 포함될 수 있으므로 현재 표식만으로 MMA 연산 자체의 정지라고 단정할 수 없다. SDK `c7x-mma-tidl/arm-tidl/rt/src/tidl_rt_ovx.c`는 vxVerifyGraph와 vxProcessGraph를 별도 호출한다. 현재 로그에는 이 구간을 구별할 근거가 없다.

다음 최소 진단은 EP debug_level 및 TIDL runtime의 기존 진단 옵션을 소스에서 확인하여 graph verify/remote create/process 전후를 노출하고, 같은 실행 직후 C71x 상태·펌웨어 trace 및 공유 로그를 수집하는 것이다. trace 출력이 비어 있으면 원래 C71x trace의 캐시 가시성도 구분한다. shared object descriptor/버퍼 주소·캐시 동기화·C71x 타깃 오류·모델 아티팩트 문제는 후보로 남기고 근거 없이 우선순위를 확정하지 않는다. 새 커널/DT/펌웨어 패치 및 모델 재컴파일은 지금 반복하지 않는다. root-only 자료의 직접 SSH 읽기는 별도 승인 범위를 준수한다.

현재 코드나 패키지를 더 변경하지 않았으며, tidl3와 noeth 및 diagnostic-lib를 유지한 상태에서 Run 내부 구간을 좁히는 것이 다음 단계다.

## run-diag.YQhftv 상세 결과

로컬 tidl-run-diag-result.tar.gz를 docs/bbai64-survey/run-diag-review/에 안전 추출하고 묶음의 SHA256을 대조했다. 상세 로그 98HdsU에서 그래프 생성, vxVerifyGraph 완료 및 C7x heap으로 network 복사 완료 메시지와 TIDL_subgraphRtCreate done을 확인했다. 이는 세션 생성 중 원격 그래프 준비가 진행됐다는 강한 근거다. after cpu_run 뒤 before tidl_run에서 timeout이며, **TIDL_subgraphRtInvoke 및 Running Graph 메시지는 보이지 않는다.** 따라서 vxProcessGraph/MMA 연산 자체의 정지로 해석할 근거는 없고 ORT Run 진입부터 EP Invoke/런타임 진입 전까지 우선 좁혀야 한다. 라이브러리 출력이 모든 경로를 완벽히 계측하는 것은 아니므로 정확한 호출 스택 확인이 필요하다.

공유 로그 스냅샷은 성공했다. C71x의 타깃 등록·초기화 완료 및 부팅 시 echo 로그는 있으나 이번 Run과 연결되는 명시적 처리 오류는 관측되지 않았다. MCU2_0의 Sciclient/DP 전원 초기화 오류는 부팅 시각의 과거 로그이며 이번 Run의 직접 원인으로 단정하지 않는다.

다음 최소 진단은 사용자 공간 probe에서 CPU/TIDL 세션의 intra/inter-op 스레드를 1개, 순차 실행으로 고정하고 spin 비활성화한 별도 후보를 준비해 동일 Run 경로를 대조하는 것이다. 이는 ORT 스레딩 대기를 분리하는 진단 가설이며 원인 확정이나 수정 성공을 보장하지 않는다. 동시에 사용자 수동 strace 또는 멈춘 프로세스 스택 수집 가이드를 준비해 futex/IPC read/ioctl 중 실제 대기를 구별한다. 커널·펌웨어·모델 재빌드는 현재 보류한다. 본 결과 분석 시점에는 새 진단 후보를 작성하지 않았다.

## ORT 스레딩 비교 후보 준비 완료

BBAI64_ORT_SINGLE_THREAD=1에서 두 세션의 intra/inter-op=1·순차·spin off를 적용하도록 probe를 수정했다. 07은 이를 선택해 기존 06 수집을 재사용한다. 선택 BBAI64_STRACE=1은 probe 시스템 호출을 timeout 안에서 수집한다. C++/shell 문법 확인, 패키지 해시 준비 완료. ARM64 링크·실기 동작 미검증, 보드 업로드·실행 미수행. [사용자 가이드](ort-thread-diagnostics-ko.md)를 제공했다.

## run-diag.fddW6r — 단일 스레드 실제 추론 통과

프로젝트 루트 ort-thread-result.tar.gz를 docs/bbai64-survey/ort-thread-review/에 추출하고 묶음의 checksum을 확인했다. FFZxxo 로그에는 ORT threads=1/순차/spin off 설정, TIDL_subgraphRtInvoke, vxProcessGraph 완료, 출력 복사 완료와 TIDL_BENCHMARK_OK가 있다. max_abs_error=0.722227로 준비한 호스트 결과(0.722229)에 근접한다. before tidl_run 3234ms, after 3240ms로 단일 호출은 로그 기준 약 6ms다. 이는 초기 단발 시험이며 정밀 성능 결과로 사용하지 않는다.

같은 실행의 레이어별 사이클 및 Sum of Layer Cycles 2473597, subgraph proc_start/end와 출력 반환을 확인했다. 기존의 단순 서비스 등록보다 강한 원격 TIDL 처리 근거이며 C71x 실행 경로를 뒷받침한다. MMA 특정 명령/하드웨어 카운터 직접 증거 및 반복 안정성은 별도로 남긴다. 코드 2는 probe 실패가 아니라 기존 스크립트의 보수적인 최종 미검증 정책이다.

스레딩 설정 묶음 변경으로 문제가 회피됐다. intra-op, inter-op, 순차 모드, spin 설정 중 어느 것이 직접 원인인지 분리하지 않았으므로 ORT 내부 deadlock을 확정하지 않는다. 해당 설정을 재현 가능한 작동 기준으로 보존하고, 지금 strace 반복·커널/펌웨어/모델 재빌드는 불필요하다. 다음은 작동 설정 기본화, 반복/수치 검증, C71x/MMA 증거를 수준별로 정리하는 단계다. 입력 버퍼 swap 불가 메시지는 이번 실행에서 copy/reformat 경로로 처리되고 추론이 완료됐으므로 그 자체를 실패로 간주하지 않는다.

## 작동 설정 기본화 및 반복 시험 준비

probe 기본 ORT 설정을 단일 스레드/순차/spin off로 고정하고 08에 warm-up 1회+측정 10회, 모든 출력 비교 및 매회 처리 구간 검사, drift·경과시간 요약을 추가했다. 05 성공 표시는 기능 검증에 한정하며 MMA 직접 증거를 분리한다. 로컬 문법 검사 통과, 보드 미실행. [사용자 가이드](repeat-validation-ko.md)를 제공한다.

## 반복 검증 완료

HcuRol/Os1IYF 결과의 checksum 45개 정상. warm-up 1+측정10회 모두 CPU 출력 비교 및 TIDL benchmark 통과. 출력 drift=0, 최대오차 0.722227, 측정 평균 5.71518ms. 반복 기능 성공이며 장시간 안정성·MMA 직접 검증과 구분한다. 상세 상태는 porting-reassessment-ko.md에 반영했다.
