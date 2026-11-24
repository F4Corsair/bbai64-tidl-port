# TIDL 구동을 위한 구성 선택과 포팅 진행 방법

이 문서는 포팅 담당자가 **무엇을 가져오고, 어떤 기능을 사용할지 결정하고, 어느 계층부터 수정할지** 정하는 안내다. 이 프로젝트의 실제 재현 명령은 [핵심 노트](01-reproduction-ko.md), 선택이 바뀐 배경은 [시행착오 노트](02-troubleshooting-ko.md)를 참고한다. 아래 기본안은 J721E의 TI ONNX Runtime TIDL EP 경로이며, 다른 SoC·릴리스에서는 구성과 지원 범위를 다시 확인해야 한다.

## 1. 실제 추론에 사용하는 구성요소

전체 흐름은 **호스트 모델 컴파일 → A72 애플리케이션/ORT → TIDL EP·TIDL-RT → TIOVX/IPC·공유 메모리 → C71x TIDL 펌웨어·MMALIB/MMA → 출력 반환**이다. Linux에서 실행하는 애플리케이션과 원격 코어의 펌웨어를 함께 준비하는 작업이다.

| 구성요소 | 역할 | 포팅할 때 선택·준비할 사항 |
|---|---|---|
| x86 호스트 TIDL Tools | ONNX 모델을 대상 SoC용 네트워크·I/O 아티팩트로 컴파일하고 양자화 보정 수행 | 타깃 런타임과 맞는 버전·SoC를 선택. 보드에 컴파일 환경 전체를 설치할 필요는 없음 |
| A72 애플리케이션·TI ORT·TIDL EP | 모델 로딩, 입력 텐서 준비, 지원 연산의 TIDL 위임, CPU 연산과 출력 관리 | 이 프로젝트는 TI ORT 1.15.0 C++ 경로. 다른 프런트엔드는 별도 호환성 검증 필요 |
| TIDL-RT / TIOVX / Vision Apps / app_utils | OpenVX 그래프·원격 타깃 생성, 버퍼·IPC·초기화 관리 | 사용한 SDK 바이너리 경로에서는 필수 의존성. 전체 데모 설치와 이 런타임 의존성은 구분 |
| C71x RTOS 펌웨어·TIDL·MMALIB | TIDL 타깃을 등록하고 원격 추론·최적화된 연산 실행 | SDK와 일치하는 이미지 또는 같은 구성으로 재빌드한 이미지. MMA 사용 근거는 별도 프로파일로 확인 |
| MAIN R5F·C66x 피어 | 배송 Vision Apps 구성의 시작 동기화·서비스 참여 | 이 모델의 TIDL 연산 대상은 C71x지만, 다른 코어를 끄려면 초기화 peer 목록과 동기화도 재구성해야 함 |
| Linux K3 remoteproc / RPMsg / TI SCI·mailbox | 원격 코어 기동·제어·메시지 전송, 전원·자원 제어 연결 | 보드 커널에서 기능 제공 여부와 실제 응답을 확인 |
| DT·펌웨어 메모리 맵 / DMA-BUF·heap | 코어별 로드 공간과 IPC·descriptor·텐서 공유 메모리 제공 | 양쪽이 같은 주소·수명·캐시 계약을 사용하도록 통합 |
| 부트로더·SYSFW·보드 지원 | Linux/코어 부팅 및 자원 배분의 기반 | 기존 보드 체인을 우선 유지하고, 충돌이 확인될 때만 필요한 부분 검토 |

정확한 DSO 연결과 초기화 피어의 근거는 [런타임 의존성 분석](../docs/tidl-ep-porting-readiness-ko.md)에 있다.

## 2. 먼저 결정할 기능과 권장 기본안

처음에는 **파일 입력의 ONNX 분류 모델 한 개 + 최소 사용자 공간 + 배송 peer 구성 유지**를 권장한다. 추론 경로를 확인한 뒤 필요한 입출력·보드 서비스를 추가하면 실패 원인을 구분하기 쉽다.

| 결정할 기능 | 선택에 따른 작업 | 이 프로젝트의 선택 |
|---|---|---|
| 파일 추론 / 카메라·디스플레이 파이프라인 | 파일은 텐서 전처리만 준비. 카메라·표시는 CSI/ISP·센서·DSS·버퍼 경로와 소유권까지 포팅 | 파일 입력으로 시작. 카메라·디스플레이 동작은 검증 범위 밖 |
| ETHFW 네트워크 서비스 | ETHFW 가상 Ethernet 포트·원격 설정·관련 gPTP/TSN 기능이 필요하면 보드 Ethernet/PHY·자원 설정을 포팅 | MCU2_0의 EVM ETHFW 초기화가 막혀 비활성화. Linux eth0/SSH는 유지됨. [기능 영향](../bbai64-porting/docs/ethfw-role-and-disable-ko.md) |
| 배송 다중 코어 구성 / C71x 중심 최소 구성 | 코어를 줄이면 A72/RTOS peer·시작 장벽·공유 영역의 초기화 주체도 변경 | C71x·C66x 두 개·MAIN R5F 두 개 유지, 기존 MCU R5F 서비스 보존 |
| SDK 바이너리 재사용 / 소스 재빌드 | 바이너리 재사용은 변경 범위가 작음. ABI·allocator·보드 초기화 차이가 확인된 구성요소만 재빌드 | TI 런타임 재사용, MCU2_0 noeth 재빌드, RPMsg 호환 라이브러리 사용 |
| 기존 Linux 유지 / TI 참조 커널 | 기존 환경 유지 시 누락된 TI 인터페이스 이식. 참조 커널도 보드 DT·부트 지원 검증 필요 | Debian·r47 기반 유지, 커널 4패치 적용 |
| C++ / Python 애플리케이션 | Python은 ORT 바인딩의 Python ABI까지 맞춰야 함 | C++로 먼저 검증하여 바인딩 차이 제외 |
| 전체 오프로딩 / 일부 CPU 실행 | 지원 연산과 EP 분할 결과에 따라 결정. CPU fallback 허용 여부는 목표 지연시간·정확도로 판단 | ResNet18 49/49 노드 위임 확인. 다른 모델에 동일 결과를 가정하지 않음 |

ETHFW를 끄는 것과 `BUILD_MCU_BOARD_DEPENDENCIES=no`는 다르다. 후자는 디스플레이·카메라 등 추가 EVM 주변장치 의존성도 바꾸므로 사용할 기능을 먼저 결정해야 한다. **배송 펌웨어 재사용은 보드의 모든 기능을 그대로 지원한다는 뜻이 아니다.**

## 3. 포팅을 진행할 순서와 단계별 산출물

| 순서 | 수행 작업 | 이 단계에서 확보할 결과 |
|---|---|---|
| 1. 실행 범위·릴리스 선택 | SoC, 모델/프런트엔드, I/O, ETHFW·peer 요구, Debian 유지 조건을 결정하고 대응 SDK 세트 고정 | 구성도·기능 선택표·버전 목록 |
| 2. Linux와 RTOS 사이 차이 조사 | 보드 부트/DT/커널 소스·설정, 펌웨어 맵, DSO 요구와 SDK 인터페이스를 비교 | 필요한 DT 변경·누락 드라이버/UAPI·재빌드 대상 목록 |
| 3. 메모리와 커널 준비 | 보드 DT에 SDK 코어/공유 영역 통합, 필요한 커널 기능 활성화 또는 최소 이식 | 서로 맞는 DT·커널 패치·이미지/모듈 후보, 복구 항목 |
| 4. 보드용 펌웨어 준비·기동 | 같은 메모리 맵/peer로 펌웨어 준비. 불필요한 EVM 서비스는 명시적으로 제외 | 코어 기동뿐 아니라 IPC 서비스·RTOS 시작 동기화 완료 |
| 5. 공유 메모리·호스트 초기화 | heap 할당/주소/동기화와 RPMsg 응답 주소 검증 후 격리 런타임 초기화 | Step 03 호스트 DMA 통과, Step 04 초기화 통과 |
| 6. 모델·실제 추론 | 같은 버전 Tools로 컴파일한 모델을 CPU와 호스트 TIDL에서 먼저 확인, 보드 EP에서 실행 | 실제 graph verify/Run/출력 반환·CPU 비교·처리 구간 |
| 7. 작동 구성 고정 | 반복 추론, 프로파일, 파일/설정 해시와 설치/복구 절차 정리 | 재현 가능한 기능 세트. 제품 정확도·성능·장시간 검증은 별도 계획 |

호스트 모델 검증은 2–5단계와 독립적으로 준비할 수 있다. 다만 보드 추론은 커널·펌웨어·공유 메모리 준비가 완료된 뒤 수행한다. 기존 C++ 재현 절차는 명시적 스레드 설정을 사용한다. 같은 포팅 구성에서 TI ORT 1.15.0, SDK의 격리된 Python 3.12 환경, TIDL Tools `11_02_04_00` 공식 Python Wrapper가 통과했다. Wrapper가 지정하는 intra-op 설정을 그대로 사용한다. 같은 ResNet18 입력으로 직접 만든 Python 세션도 스레드 옵션을 모두 기본값으로 둔 경우에 통과했다. 다른 구성에서는 Python ABI와 TIDL EP 가용성을 점검하고, 양의 TIDL 처리 구간과 CPU 출력 비교로 실제 오프로딩을 확인한다. [Python 실행 가이드](../bbai64-porting/python-ort-validation/README-ko.md), [보드 검증 결과](../bbai64-porting/python-ort-validation/results-ko.md)

## 4. 커널 패치와 드라이버 이식은 어떻게 수행하는가

### 먼저 기능을 활성화할지, 코드를 옮길지 판단한다

실행 커널과 동일한 소스·설정을 확보하고, SDK 사용자 공간이 실제로 호출하는 장치·ioctl·sysfs와 대조한다. 구현이 이미 있으면 Kconfig/모듈/DT 연결을 먼저 맞춘다. 구현이 없을 때만 대응 TI 커널에서 필요한 기능을 가져온다. 커널 버전 번호나 장치 파일 존재만으로 지원 여부를 판단하지 않는다.

### 이 프로젝트에서 필요했던 최소 변경

| 변경 | 왜 필요한가 | 이식 시 함께 검토할 경계 |
|---|---|---|
| 0001: TI carveout DMA heap exporter | SDK가 고정 예약 메모리에서 공유 버퍼를 할당 | DT compatible·예약 등록 시점·DMA-BUF exporter API·cache sync·할당 실패 정리 |
| 0002: remoteproc DMA-BUF 주소 조회 ioctl | SDK allocator가 DSP와 공유할 버퍼 주소를 조회 | UAPI 크기/정렬·권한·attach/map/unmap·fd 수명·주소 연속성 |
| 0003: K3 DMA 부모 장치 매핑 | DMA 설정이 없는 remoteproc 클래스 장치로 매핑하면 실패 | DMA mask·IOMMU·실제 플랫폼 부모·DMA주소와 PA의 관계 |
| 0004: RPMsg 실제 local 주소 노출 | ANY 요청값 -1 대신 실제 할당 주소를 TIOVX 응답 포트로 전달 | endpoint open/release 잠금·sysfs 의미·동적 할당/충돌 처리 보존 |

이 4개 패치는 r47용 구현이다. 다른 릴리스에 모두 필요하다고 가정하지 않는다. [패치와 근거](../bbai64-porting/patches/README-ko.md), [DMA 이식 분석](../bbai64-porting/patches/ti-dma-backport-ko.md).

### 실제 이식 작업 흐름

1. **변경 단위를 나눈다:** exporter, 주소 조회, RPMsg처럼 사용자 공간 계약별로 패치를 분리한다. 관련 헤더·Kconfig·Makefile까지 포함한다.
2. **목적지 API에 맞춘다:** TI 파일을 단순 복사하지 않고 대상 커널의 DMA-BUF API·namespace·device lifetime·오류 해제·잠금·접근 제어에 맞춘다. 사용자 공간 ABI를 유지할지 같이 변경할지 명시한다.
3. **기존 기능을 보존한다:** remoteproc 자동 종료·MCU 서비스 등 이번 기능과 관계없는 동작을 바꾸지 않는다. 주소를 임의 상수로 대체하거나 보안 제한을 제거해 통과시키지 않는다.
4. **정적/빌드 검사를 한다:** 순차 적용·diff·UAPI 크기·메모리 범위 및 관련 객체를 확인하고, 새 릴리스 이름의 전체 이미지와 일치 모듈을 사용자가 빌드한다.
5. **계층별로 시험한다:** 복구 가능한 부트 항목으로 적용한 뒤 heap/ioctl/RPMsg 실제 주소 → TIOVX 초기화 → 실제 추론 순서로 검증한다. 이미 통과한 경계를 근거 없이 다시 수정하지 않는다.

커널이 제공할 주소·버퍼 계약이 달라 기존 바이너리로 맞출 수 없다면 allocator/런타임 소스 이식도 대안이다. 반대로 RTOS linker/MMU 변경은 Linux 드라이버 패치만으로 해결되지 않으므로 DT와 펌웨어를 함께 검증해야 한다. 커널 소스/패치는 로컬 준비, 커널 빌드·배포와 모든 보드 적용은 사용자가 수행하는 역할을 유지한다.

## 5. 추가 체크사항

아래는 구성과 진행 방향을 정한 뒤 적용하는 세부 검토 목록이다.

### 5.1. 버전 세트를 먼저 고정

TIDL Tools/모델 importer, ARM runtime/EP/ORT, C71x TIDL/MMALIB, Vision Apps/TIOVX/app_utils, RTOS·PDK·SYSFW, Linux UAPI를 각각 기록한다. 마케팅상 11.02가 같다는 이유만으로 교환하지 않는다. 도구 태그·커밋·바이너리 해시·SONAME·의존 심볼·실제 로딩 경로가 근거다. 공식 J721E 11.02 RTOS 문서는 Linux11.02.00.04/TIDL11_02_04_00/MMALIB11_02_00_06을 명시한다. [공식 구성](https://software-dl.ti.com/jacinto7/esd/processor-sdk-rtos-jacinto7/11_02_00_06/exports/docs/psdk_rtos/docs/user_guide/sdk_components_j721e.html)

### 5.2. 보드/부트/메모리 계약

- SoC·보안 GP/HS·서명 요구·부트 저장장치·실제 extlinux 항목·initrd 포함 펌웨어 확인.
- 보드 DTS include/overlay를 보존하고 reserved-memory와 ELF LOAD/resource table/trace/vring/공유 descriptor를 대조.
- memory-region 순서와 phandle을 실제 커널 드라이버로 검증. C66 DMA 풀 이름만 보고 의도 추정 금지.
- DMA 주소=물리주소 가정, IOMMU·연속성·주소폭·cache sync·CMA/전용 heap을 확인. 일반 heap 이름 변경은 호환 패치가 아님.
- SYSFW 자원 배분·IRQ/UDMA·MMA 관련 설정은 Sciclient 일부 성공만으로 전체 호환이라 판단하지 않음.

### 5.3. 호스트/커널/RTOS 경계

커널 기능 설정과 실제 동작을 함께 검사한다. 이 프로젝트의 TI ioctl/exporter 패치를 다른 커널에 그대로 적용하지 말고 ABI·장치 lifetime·DMA parent·보안 제한을 재검토한다. RPMsg 자동 할당 요청값 ANY와 실제 주소를 구분한다. 주소를 상수로 바꾸지 말고 커널 할당/반환을 맞춘다. SDK/OS ORT를 격리하고 Debian GLIBC가 더 최신이라는 사실만으로 전체 ABI 호환을 보장하지 않는다.

EVM 펌웨어는 GESI/QENET·DSS/I2C·pinmux 등에 의존할 수 있다. ETHFW 제외는 이번 BBAI64의 선택이며 모든 보드의 필수 설정이 아니다. Ethernet 가상 포트·gPTP/TSN 관련 기능을 요구하면 별도 보드 지원이 필요하다. R5F/C71x trace와 일반 공유 로그는 다르며 캐시 가시성 및 과거 로그를 구분한다.

### 5.4. 모델/양자화 계약

SoC와 Tools를 고정하고 모델·아티팩트·입력·전처리를 해시로 한 세트 관리한다. RGB/BGR, NCHW/NHWC, shape/dtype, mean/scale, byte order를 확인한다. 호스트 CPU/TIDL 성공은 전처리/파일 오류를 줄여 주지만 C71x 코드 생성·자원 문제까지 배제하지 않는다. calibration2/iterations5·한 이미지 top1 일치는 제품 정확도 검증이 아니다. 대표 보정/평가 데이터와 수용할 정확도 손실은 용도별로 정한다.

### 5.5. 성공 수준과 중단 기준

1. 장치 열거 → 초기화 → 실제 graph verify/remote create → Run/출력 반환 순서로 구분한다.
2. CPU 대비 오차·유한값·shape·반복 drift·각 실행의 benchmark 구간을 확인한다.
3. C71x 경로와 MMA 직접 프로파일을 분리한다. 레이어 사이클만으로 특정 MMA 명령을 직접 증명했다고 하지 않는다.
4. debug 포함 host Run 시간과 순수 가속 시간·제품 성능을 혼합하지 않는다.
5. timeout은 마지막 표식·스택/시스템 호출로 좁히고, 근거 없이 연장/재컴파일하지 않는다.

**확인됨/가능성 높음/미확인**으로 판단을 기록한다. 계속 진행은 수정 가능한 구간이 특정될 때, 조건부 진행은 필요한 소스·도구·복구 수단을 확보할 수 있을 때, 보류는 그 필수조건을 확보할 수 없을 때다. Debian 유지가 불가능하다는 결론은 구체적인 막힌 인터페이스가 근거여야 한다.

## 6. summary/files의 범위

포함: 커널4패치·빌드설정/스크립트, noeth 재빌드 패치/도구, 기준/후보DT·맵, 검증 스크립트·ORT 헤더/실행기 소스, 소형 RPMsg0.6.11 진단 라이브러리, SDK 원본 경로/해시 매니페스트와 선택 추출기. 라이브러리의 사용 조건은 원 TI SDK 라이선스를 따른다. RPMsg 라이브러리의 진단 패치와 TI 라이선스는 files/rpmsg-work에 동봉했다.

제외: Linux/SDK 전체 소스, 커널 image/전체모듈, SDK runtime 대형 바이너리, RTOS ELF, 모델/아티팩트, Docker 이미지와 과거 trace 전체. 원 프로젝트와 고정 SDK에서 선택 생성한다. 큰 파일이 필요 없는 것은 아니며 summary 중복 보관을 생략한 것이다. 이 세 문서는 원 프로젝트를 참조하는 인덱스이므로 보조 링크까지 쓰려면 원 프로젝트도 보존한다.
