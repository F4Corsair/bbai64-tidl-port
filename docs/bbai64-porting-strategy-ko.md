# BBAI64 TIDL EP 실기 조사 및 포팅 전략

## Executive Summary

**CONDITIONAL GO.** 실기는 Debian 13.6 / `6.18.39-arm64-k3-r47`에서 K3 DSP·R5F remoteproc을 제공한다. 현재 C71x, C66x 및 MAIN R5F는 오프라인이고 부팅 로그에 펌웨어 요청 실패 `-2`가 있다. 현재 DT에서는 SDK의 Vision Apps C71x ELF를 로드할 수 없다. Vision Apps가 여는 carveout heap도 현재 노출되지 않는다. [실기 로그](bbai64-survey/board.log)

첫 구현은 **전략 A**를 권장한다. 기존 Debian 및 부트 체인을 보존하고, 복구 가능한 시험 SD에서 BBAI64용 DT와 SDK 제공 RTOS 펌웨어를 한 세트로 적용한다. 커널 보완 범위는 실제 소스에서 heap exporter와 TI 주소 조회 ioctl을 확인한 뒤 결정한다. AArch64 시스템 라이브러리는 정적 검사에서 재사용에 유리하다. Debian ORT 1.21 및 Python 3.13이 설치되어 있으므로, TI ORT 1.15.0과 EP는 격리된 C++ 경로에서 먼저 검증한다. [ABI·커널 심볼](bbai64-survey/interfaces.log)

## Part 1. 알아낸 점

### OS, 커널 및 부트 체인

- **확인됨** — 보드는 BeagleBone AI-64, BeagleBoard.org Trixie Xfce 이미지(2026-07-24), Debian 13.6, AArch64 PREEMPT_RT `6.18.39-arm64-k3-r47`이다. 커널·헤더 패키지 버전은 `1trixie`, 소스 패키지는 `linux-upstream 1trixie`다. 정확한 소스 커밋과 공급사 패치 세트는 **미확인**이다. [실기 로그](bbai64-survey/board.log) · [추가 조회](bbai64-survey/interfaces.log)
- **확인됨** — 루트는 `mmcblk1p3`, `/boot/firmware`는 `mmcblk1p1`이며 extlinux 메뉴는 microSD로 구성되어 있다. 해당 파티션의 U-Boot 파일 문자열은 `2026.01-g5c82fb688432`이다. TI SCI 드라이버는 펌웨어 `11.2.8--v11.02.08`, ABI 4.0을 보고했다. **미확인** — 실제 SPL/U-Boot가 로드된 매체 및 TIFS/DM 각각의 버전·보안 변형. UART 부트 로그와 이미지 메타데이터를 대조한다. [부팅 및 TI SCI 로그](bbai64-survey/board.log)

### 유효 DT와 메모리 맵

**확인됨** — `/proc/device-tree`의 전체 속성을 읽어 phandle을 해석했다. `/sys/firmware/fdt`는 root 전용이어서 live DT를 근거로 사용했다. 부팅 파티션의 BBAI64 DTB도 복사했으며 기본 extlinux 항목의 `fdtoverlays`는 주석 처리되어 있다. 부트로더 fixup과 정확한 DTB 선택 이력은 **미확인**이다. [live DT 해석](bbai64-survey/live-dt-summary.txt) · [부팅 파티션 DTB](bbai64-survey/boot-bbai64.dtb)

| 노드 | 실기 DMA → 펌웨어 시작 | SDK Vision Apps DMA → 펌웨어 시작 |
|---|---|---|
| C71x | `a8000000 → a8100000` | `b2000000 → b2100000` |
| C66 DSP0 | `a7000000 → a6100000` | `a9000000 → a8100000` |
| C66 DSP1 | `a6000000 → a7100000` | `a8000000 → a9100000` |
| MAIN R5F0_0 | `a2000000 → a2100000` | `a2000000 → a2100000`, 펌웨어 영역 15 → 31 MiB |
| MAIN R5F0_1 | `a3000000 → a3100000` | `a4000000 → a4100000`, 펌웨어 영역 15 → 31 MiB |
| MAIN R5F1_0/1 | `a4000000 → a4100000`, `a5000000 → a5100000` | `a6000000 → a6100000`, `a7000000 → a7100000` |
| MCU R5F0_0/1 | `a0000000 → a0100000`, `a1000000 → a1100000` | 동일 |

- **확인됨** — 이전 분석의 SDK 동봉 BBAI64 기본 DTB는 C66 DMA가 연속 쌍이었지만 실기에서는 교차한다. 인덱스 0은 DMA 풀이고 인덱스 1은 펌웨어 영역이다. MAIN 두 클러스터의 `ti,cluster-mode`는 0, MCU 클러스터는 1이다. 표의 SDK 값과 ELF 로드 근거는 이전 정적 분석에서 가져왔다. [live DT 해석](bbai64-survey/live-dt-summary.txt) · [SDK 비교](tidl-ep-porting-readiness-ko.md#section-06)
- **확인됨** — live DT의 정적 `reserved-memory/reg` 구간끼리 겹치지 않는다. RAM은 `[0x80000000,0x100000000)`와 `[0x880000000,0x900000000)`다. 부팅 로그상 CMA는 `[0xf3e00000,0xfce00000)`(144 MiB)로, SDK의 C71x 영역 `[0xb2100000,0xb8000000)` 및 공유 heap `[0xb8000000,0xd8000000)`과 겹치지 않는다. 반면 새 C71x 영역만 추가하면 SDK의 나머지 영역은 기존 DSP·R5F와 충돌한다. 실기 IPC `[0xaa000000,0xabc00000)`도 SDK의 끝 `0xac000000`까지 확장해야 한다. [전체 예약 구간](bbai64-survey/live-dt-summary.txt) · [CMA 로그](bbai64-survey/board.log)
- **추정** — BBAI64 보드 설정을 유지한 채 충돌하는 예약 영역과 해당 코어 참조를 함께 교체하면 SDK 주소 체계를 적용할 수 있다. IPC·descriptor·공유 heap·C7x high heap을 포함해야 한다. EVM DTBO를 그대로 적용하려면 외부 심볼과 EVM 전용 ETHFW 참조가 모두 해결되는지 검증해야 한다. BBAI64용 최소 통합이 우선이다. 접근이 제한된 물리 주소 정보와 원본 FDT의 예약 테이블까지 대조한 뒤 최종 충돌 여부를 판정한다.

### Remoteproc, 펌웨어 및 IPC

**확인됨** — `remoteproc0/1`은 C66 DSP0/1, `remoteproc2`는 C71x, `remoteproc5/6`은 MAIN R5F0_0/1, `remoteproc7/8`은 MAIN R5F1_0/1이다. 모두 오프라인이다. 요청 이름은 각각 `j7-c66_{0,1}-fw`, `j7-c71_0-fw`, `j7-main-r5f{0,1}_{0,1}-fw`다. 표준 경로와 압축 변형 조회에서 대응 파일·링크가 나오지 않았으며, 기존 로그의 직접 로드 실패는 `-2`다. `remoteproc3`의 MCU R5F는 이미 `attached`이며 이 코어에 virtio0, RPMsg char/control 및 ping-pong 채널이 존재한다. [remoteproc·장치·부팅 로그](bbai64-survey/board.log)

**추정** — MAIN R5F/C66 피어의 커널 probe는 완료되었으므로 준비된 DT·펌웨어와 적절한 TI SCI 자원 구성이 있으면 시험할 수 있다. 현재 자료로 Vision Apps 동기화 성공은 확인할 수 없다. 이미 붙은 MCU R5F와 기존 시스템 서비스를 보존한다. SDK ELF의 버전·로드 맵과 코어 동기화 근거는 이전 보고서에 있다. [SDK ELF와 RTOS 초기화](tidl-ep-porting-readiness-ko.md)

### DMA heap과 커널 보완 범위

| 인터페이스 | 판정 및 다음 확인 |
|---|---|
| K3 remoteproc, TI SCI, virtio RPMsg 및 RPMsg char | **확인됨.** 설정과 실제 probe/MCU endpoint 확인. C71x용 endpoint는 펌웨어 기동 후 별도 확인. |
| 표준 DMA-BUF/CMA | **확인됨.** `system`, `default_cma_region`, `reserved` 장치가 있고 CMA 및 시스템 heap 설정이 켜져 있다. 데이터 공유와 캐시 일관성은 **미확인**이다. |
| Vision Apps carveout heap | **확인됨.** `/dev/dma_heap/carveout_vision_apps_shared-memories`가 현재 없다. 조사한 설정과 심볼에서 TI carveout exporter 근거를 찾지 못했다. 정확한 커널 소스에서 `dma-heap-carveout` 바인딩과 exporter 구현을 확인해야 한다. |
| `RPROC_IOC_DMA_BUF_ATTACH` | **미확인.** `CONFIG_REMOTEPROC_CDEV=y`, `rproc_device_ioctl` 심볼과 char 장치 존재는 확인됐다. 해당 ioctl의 dispatch를 보여주는 정확한 소스는 보드 헤더에 없었다. ioctl은 호출하지 않았다. |
| 디바이스 번호 및 권한 | **확인됨.** 배송 allocator의 `/dev/remoteproc0`은 실기에서 DSP0이다. 대상 장치에 대한 attach의 주소 의미를 소스로 확인하고 안정적인 코어 식별을 사용한다. 현재 remoteproc, rpmsg 및 heap 장치는 root 전용이고 `/dev/mem`은 `root:kmem` 0640이다. 런타임 권한과 mmap 요건은 별도 설계가 필요하다. |

[커널 설정](bbai64-survey/kernel.config) · [심볼 및 장치 로그](bbai64-survey/interfaces.log) · [SDK allocator 분석](tidl-ep-porting-readiness-ko.md#section-07)

커널 기능이 빠졌다면 우선 TI 6.12 계열의 carveout exporter, 바인딩, remoteproc cdev·UAPI·DMA 매핑을 대상 브랜치와 대조한다. 필요한 부분만 옮기는 방법은 SDK 사용자 공간을 보존하지만 커널 API 적응과 권한 검증이 필요하다. 기존 커널을 그대로 쓰고 allocator를 바꾸는 방법은 지원 heap 선택, DSP에 유효한 주소 획득, 버퍼 수명·캐시 동기화까지 다시 검증해야 하므로 이름 교체보다 범위가 크다. 차이가 크면 TI 계열 커널을 별도 SD에 두고 펌웨어·런타임 기준 시험에 사용한다.

### TIDL Runtime 및 ABI

**확인됨** — 실기 glibc 2.41 및 libstdc++6 14.2는 이전 SDK 검사에서 확인한 `GLIBC_2.38`, `GLIBCXX_3.4.32`를 포함한다. `libEGL.so.1`, `libGLESv2.so.2`, `libgbm.so.1`도 로더 캐시에 있다. Debian ORT는 1.21, Python은 3.13이며 SDK ORT는 1.15.0 및 Python 3.12 확장이다. 실기 로더 캐시에서 TI TIDL·Vision Apps·RPMsg DSO를 확인하지 못했다. [실기 ABI](bbai64-survey/interfaces.log) · [SDK ELF·SONAME 분석](tidl-ep-porting-readiness-ko.md#section-08)

**추정** — TI ORT 1.15.0, `libtidl_onnxrt_EP`, `libvx_tidl_rt`, `libtivision_apps`, `libti_rpmsg_char`와 대응 provider 라이브러리를 동일 릴리스에서 가져와 별도 경로에 두면 재사용 가능성이 높다. 동일 이름의 시스템 `libonnxruntime_providers_shared.so`가 섞이지 않도록 경로를 검증한다. SDK Python 확장 대신 C++로 시작한다. 실제 동적 로딩, 간접 의존, EP 등록과 IPC 실행은 **미확인**이다. J721E 버전 기준은 Linux 11.02.00.04, RTOS 11.02.00.06, Tools 11_02_04_00이다. [이전 버전 및 ABI 검증](tidl-ep-porting-readiness-ko.md)

## Part 2. 포팅 전략 및 사용자의 선택 사항

| 우선순위·전략 | 구현 가능성 및 수정 범위 | 위험·추가 검증·선택 시점 |
|---|---|---|
| 1. **A — Debian + SDK 바이너리** | 기존 OS 유지. BBAI64 DT와 펌웨어를 함께 적용. 필요한 경우 TI heap/ioctl만 커널에 추가. RTOS 재빌드는 초기 범위 밖. | RTOS 초기화 피어, high heap 및 자원 소유권, 커널 기능과 로더 검증이 선행 조건. 현재 우선 선택. |
| 2. **B — A72 일부 재빌드** | OS·RTOS를 유지하고 ABI 또는 allocator 문제에 해당하는 DSO만 동일 헤더로 재빌드. 커널 유지 가능성은 주소 조회 대안에 달려 있다. | 호스트/펌웨어 프로토콜, C++ ABI, Python ABI 확인. A의 로딩·메모리 실패 범위가 확정된 후 선택. |
| 3. **C — RTOS·메모리 재구성** | OS 유지. C71x 및 필요한 피어의 펌웨어, IPC 동기화, linker/MMU·DT와 A72 구성 동시 수정. | 코어 축소 및 재배치로 검증 범위 증가. A의 주소·피어 충돌이 해소되지 않을 때 선택. |
| 비교용 **D — TI 커널 별도 시험** | 기존 Debian을 보존한 별도 SD에 TI 계열 커널과 BBAI64용 부팅 구성을 준비. SDK RTOS 재사용 시도. | 보드 지원과 부트 호환성 검증 필요. TI 전용 커널 기능의 이식 비용이 크거나 원인 분리가 필요할 때 선택. |

지금 필요한 결정은 **시험 SD와 UART 기반 복구 환경을 마련해 A를 진행할지**다. 커널 패치, A72 재빌드, RTOS 축소 여부는 소스·실험 결과로 확정한다.

## Part 3. 향후 필요한 작업

| 순서 | 수정 대상 및 수행 작업 | 성공 기준 | 실패 시 대안·복구 | 승인 |
|---|---|---|---|---|
| 1. 시험 환경 | 별도 SD와 UART, 원본 extlinux 항목·이미지 해시, 복구 부팅 절차 확보 | 원본 구성 재부팅 및 복귀 확인 | 원본 SD로 복귀, eMMC 보존 | 매체 쓰기·재부팅 승인 |
| 2. DT | 별도 소스 트리의 BBAI64 DTS/DTBO에서 코어 및 공유 영역 통합. 오프라인 병합·phandle·ELF 검사 | 중복 0건, 필요한 코어와 SDK PA/DA 맵 정합 | 충돌한 fragment만 보정, 해결 불가 시 C 평가 | DT 수정·빌드 승인 |
| 3. 커널 | 정확한 커널 소스에서 exporter 및 ioctl dispatch 비교. 필요한 경우 heap 드라이버, 바인딩, remoteproc cdev/UAPI만 이식 | 필요한 장치와 주소 조회 경로가 확인됨 | 별도 TI 커널 시험 또는 B의 allocator 이식 | 로컬 비교 가능, 빌드·설치 승인 |
| 4. 펌웨어 | SDK ELF·서명 변형과 DT를 시험 항목에 함께 배치. C71x와 초기화 피어, 기존 MCU attach 상태 확인 | 로딩·기동 및 피어 동기화 성공 | 원본 DT와 펌웨어 세트로 함께 복귀 | 배치·상태 변경 승인 |
| 5. IPC/DMA | RPMsg endpoint, heap 할당·매핑·주소 조회, CPU/DSP 양방향 패턴과 캐시 일관성 시험 | 반복 교환 성공, 할당·주소·캐시 오류 없음 | 커널/UAPI와 코어 매핑부터 재검토 | 보드 시험·ioctl 승인 |
| 6. TIOVX/TIDL | 격리 DSO 디렉터리와 실행기에서 로더 경로, `appInit`, IPC·타깃 등록 검사 | 올바른 SONAME 세트, TIOVX 초기화 성공 | ABI 실패 범위에 맞춰 B 선택 | 배치·보드 실행 승인 |
| 7. ONNX EP | Tools로 단일 ONNX 모델 컴파일, TI ORT 1.15.0 C++에서 파일 입력 실행 | 동일 입력의 CPU 기준 출력과 허용오차 내 일치 | 아티팩트·EP ABI·로더부터 분리 확인 | 도구 설치·보드 실행 승인 |
| 8. 오프로딩 | EP의 위임 서브그래프와 C71x TIDL 펌웨어 프로파일·실행 로그 확인 | 위임 1개 이상과 C71x/MMA 실행 근거, 반복 결과 일치 | CPU fallback은 미통과. 모델 지원 연산 및 타깃 재확인 | 보드 시험 승인 범위 |
| 9. 재현 | 시험 이미지, 버전·해시, 설치와 롤백 절차 정리 | 새 시험 환경에서 콜드부트 후 재현 | 마지막 통과 세트로 복귀 | 매체 쓰기·재부팅 승인 |

Codex가 다음에 바로 할 수 있는 준비는 **수집 DT를 기준으로 교체 대상 노드와 충돌 구간 목록 작성 → 대상 커널 소스 리비전 추적 및 ioctl/exporter 정적 대조 → TI DSO/펌웨어 해시 목록과 단일 모델 검증 기준 작성** 순이다. 실제 변경은 구현 지시 후 수행한다.

### 결론

1. Debian 유지 포팅은 현실적인 우선 경로다. 커널 공유 메모리 계약 검증이 선행 조건이다.
2. SDK Vision Apps 펌웨어는 대응 DT와 RTOS 피어를 구성하면 재사용할 후보다. 현재 DT에는 바로 적용할 수 없다.
3. DT 수정 범위는 충돌 carveout, 활성 피어의 remoteproc 참조, IPC·descriptor·DMA heap·코어 heap이다. BBAI64 주변장치와 부팅 설정을 보존한다.
4. 커널 보완 후보는 TI carveout exporter와 주소 조회 ioctl이다. 정확한 소스 대조로 구현 유무를 확인하고 필요한 기능만 보완한다.
5. SDK A72 바이너리는 정적 ABI상 유력하다. TI ORT 1.15.0과 EP를 격리해 실제 로딩을 검증한다.
6. 전략 A를 우선한다. B와 C는 해당 실패가 확인되면, D는 커널 문제 분리가 필요할 때 선택한다.
7. 복구 환경 → DT/ELF 정합 → 커널 기능 → 펌웨어/IPC → 공유 메모리 → TIOVX/TIDL → ONNX EP 및 가속 증거 → 재현 순으로 진행한다.

### 수행 명령과 수집 파일

- [주 조회 명령](bbai64-survey/commands.sh) 및 [출력](bbai64-survey/board.log). 최초 모델 식별은 `tr '\000' '\n' </proc/device-tree/model`을 사용했다.
- [live DT 아카이브](bbai64-survey/live-dt.tar)는 원격 `tar -C /proc/device-tree -chf - .`의 stdout을 로컬에 저장한 것이다. [정적 해석](bbai64-survey/live-dt-summary.txt)은 로컬에서 생성했다.
- [부트 DTB](bbai64-survey/boot-bbai64.dtb)는 원격 `cat /boot/firmware/ti/k3-j721e-beagleboneai64.dtb`, [커널 설정](bbai64-survey/kernel.config)은 원격 `zcat /proc/config.gz` 또는 대응 `/boot/config-*` 조회로 수집했다.
- [추가 출력](bbai64-survey/interfaces.log)은 `dpkg-query`, 헤더·System.map `ls`, System.map/kallsyms `grep`, `/sbin/ldconfig -p`, U-Boot 파일 `strings` 조회 결과다.

기존 SSH 설정을 사용해 일반 사용자 권한으로 조회했고 수집 파일은 로컬에만 저장했다. 원격 파일 쓰기, 설치, 재부팅, 모듈·서비스 조작, remoteproc 상태 변경 및 ioctl 호출은 수행하지 않았다.

## 후속 실기 조사 — Vision Apps DMA heap

현재 부팅에서 `vision_apps_shared-memories` 노드의 compatible은 `dma-heap-carveout`이고, 부팅 로그에 512 MiB 예약 범위 `[0xb8000000, 0xd8000000)`가 확인된다. SDK가 요구하는 heap은 sysfs와 `/dev` 양쪽에서 미등록 상태다. 표준 heap 3개는 양쪽에 표시된다. C71x `remoteproc2`의 RPMsg 제어 및 문자 서비스 등록도 확인했다.

실행 커널의 모듈·내장 모듈 목록, 설정 및 심볼에서는 TI exporter 지원 근거가 확인되지 않았다. `rproc_device_ioctl`은 존재하지만 해당 TI ioctl의 처리 분기는 설치된 헤더 트리에서 확인할 수 없었다. 두 구현의 유무는 정확한 실행 커널 소스와 패치 구성에 대한 확인이 남아 있다.

기존 `beagle` SSH 별칭에서 일반 사용자 권한으로 live DT, 장치 목록, 커널 설정, 모듈·심볼, 부팅 로그와 RPMsg 경로를 읽었다. [수행 명령](bbai64-survey/dma-followup.sh) · [수집 로그](bbai64-survey/dma-followup.log) · [포팅 판단](../bbai64-porting/docs/bringup-status-ko.md)

<a id="section-14"></a>

## r47 커널 소스 확인

설치된 `linux-image-6.18.39-arm64-k3-r47` 패키지 버전은 `1trixie`다. 공개 커널 저장소에서 같은 릴리스의 태그를 찾았다. 태그가 가리키는 커밋은 `c03783811916b255c974912b3fd2eceb30fa8146`이며, 커밋 메시지도 r47 빌드를 명시한다. 관련 defconfig 설정은 실기 설정과 일치한다. 이 대조는 릴리스 소스 식별 근거이며 설치 이미지와 소스의 재현 빌드 비교는 수행하지 않았다. [패키지 출처 로그](bbai64-survey/kernel-origin.log) · [r47 커밋](https://github.com/RobertCNelson/linux-stable-rcn-ee/commit/c03783811916b255c974912b3fd2eceb30fa8146)

| 기능 | r47 소스 판정 |
|---|---|
| Vision Apps carveout exporter | **누락.** heap 빌드 목록에 system과 CMA만 있다. CMA legacy 이름은 기본 CMA의 추가 이름이며 DT의 `dma-heap-carveout` 영역을 별도 heap으로 등록하는 경로가 아니다. [heap 빌드 목록](https://github.com/RobertCNelson/linux-stable-rcn-ee/tree/c03783811916b255c974912b3fd2eceb30fa8146/drivers/dma-buf/heaps) |
| `RPROC_IOC_DMA_BUF_ATTACH` | **누락.** `rproc_device_ioctl`은 shutdown-on-release 설정과 조회만 처리한다. SDK가 사용하는 DMA-BUF attach 명령은 기본 분기의 `-EINVAL`에 해당한다. 이는 소스 판독 결과이며 실기 ioctl 호출은 수행하지 않았다. [remoteproc 구현](https://github.com/RobertCNelson/linux-stable-rcn-ee/blob/c03783811916b255c974912b3fd2eceb30fa8146/drivers/remoteproc/remoteproc_cdev.c) · [SDK 요청 정의](../bbai64-porting/src/dma_buf_phys.h:33) |

SDK 바이너리를 재사용하는 경로에는 512 MiB 예약 영역을 노출하는 exporter와 SDK ABI에 맞는 주소 조회 기능이 모두 필요하다. 다음 구현 범위는 SDK와 대응하는 TI 커널 구현을 찾아 r47에 최소 이식할 수 있는지 평가하는 것이다. 패치 작성이나 보드 적용은 이 조사 범위에 포함하지 않았다.


## 2026-11-18 Step 04 후속 읽기 전용 조사

SSH로 커널·remoteproc·RPMsg 목록·펌웨어 링크 및 해시·dmesg를 수집했다. 명령과 결과는 `docs/bbai64-survey/rpmsg-followup-20261118.log`, 분석 및 다음 작업은 [IPC 장애 보고서](../bbai64-porting/docs/rpmsg-failure-analysis-ko.md)에 기록했다. 원격 변경과 관리자 조회는 수행하지 않았다.


## 진단 펌웨어 적용 전 initramfs 확인

2026-11-18 읽기 전용 SSH로 uname, /proc/cmdline, /boot 및 /boot/firmware 목록, /boot/firmware/extlinux/extlinux.conf를 조회했다. 실행 표식은 tidl-kernel-test이며 해당 기본 항목은 Image-6.18.39-arm64-k3-r47-tidl2.gz 및 후보 DT를 지정하고 initrd 지시문이 없다. 실행 커널명에 대응하는 /boot/initrd.img 파일 부재 때문에 initramfs를 생성할 필요는 없다. 기존 /boot/initrd.img-6.18.39-arm64-k3-r47의 lsinitramfs 목록에서도 대상 펌웨어 이름은 관측되지 않았으나, 적용 판단의 주 근거는 현재 선택 항목에 initrd 지시문이 없다는 점이다. 원격 변경은 수행하지 않았다.


## 진단 펌웨어 적용 후 수집

일반 SSH 읽기로 사용자 저장 trace, remoteproc/RPMsg 목록, dmesg, 펌웨어 링크·해시를 `docs/bbai64-survey/trace-firmware-result-20261118.log`에 수집했다. 사용자에게 이번 로그 및 trace의 sudo 읽기를 별도 승인받았으나 sudo -n은 암호 요구로 실패했다. 사용자가 상세 로그를 전달했다. 분석은 [IPC 장애 보고서](../bbai64-porting/docs/rpmsg-failure-analysis-ko.md)의 진단 펌웨어 적용 후 절에 기록했다.


## 캐시 반영 trace 결과

사용자 저장 trace-wb의 trace0/remoteproc/RPMsg/dmesg와 현재 펌웨어 링크·해시를 일반 사용자 읽기로 수집했다. 원본은 `docs/bbai64-survey/trace-wb-result-20261118.log`. Sciclient·UDMA·메모리 초기화 성공 뒤 appEthFwInit 진입 전 표식에서 끝난다. 상세 판단 및 ETHFW 제외 후보의 다음 검증 기준은 [장애 분석](../bbai64-porting/docs/rpmsg-failure-analysis-ko.md)에 기록했다. 원격 변경 없음.


## noeth 후보 준비와 네트워크 사전 조회

일반 사용자 읽기 전용 SSH로 ip -br link 및 /sys/class/net/*/device/driver를 조회했다. eth0 드라이버는 am65-cpsw-nuss였다. 원본은 docs/bbai64-survey/noeth-network-precheck-20261118.log. ETHFW 제외 후 네트워크 유지 보장은 아니며 SD 복구를 유지한다. 독립 로컬 noeth 펌웨어 빌드·검증 및 사용자 수동 적용 가이드를 준비했다. 원격 업로드·변경 없음.

## 포팅 재평가 자료 수집 및 진단 준비

일반 사용자 SSH로 uname, GLIBC, 모델·입력·net/io/meta·런타임 해시 및 C71x 상태를 수집했다. 원본은 docs/bbai64-survey/reassessment-board-20261118.log. 로컬과 해시가 일치한다. 고정 Docker에서 공식 전처리 및 CPU/호스트 TIDL 추론을 별도 복사본으로 재실행했다. 결과는 tidl/reassessment/와 [재평가 보고서](../bbai64-porting/docs/porting-reassessment-ko.md). 다음 보드 실행은 사용자 수동 가이드로 준비했으며 원격 업로드·관리자 읽기·추론 실행은 수행하지 않았다.
