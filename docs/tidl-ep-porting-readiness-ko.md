# BBAI64 TIDL EP 포팅 준비도 분석

## Executive Summary

**CONDITIONAL GO.** J721E용 **PSDK RTOS 11.02.00.06 / Linux 11.02.00.04 / TIDL Tools 11_02_04_00 / TI ONNX Runtime 1.15.0**을 고정하고 준비 작업을 시작할 수 있다. Debian 13 / Linux 6.18의 실기 호환성은 별도로 확인해야 한다. [TI 태그의 버전 표](https://github.com/TexasInstruments/edgeai-tidl-tools/tree/11_02_04_00#version-compatibility)

- **확인됨** — ONNX EP는 `libvx_tidl_rt.so`를 동적으로 열고, 이 라이브러리는 `libtivision_apps.so.11.2.0`에 직접 의존한다. TIDL-RT가 OpenVX 그래프를 만들고 TIOVX가 C71x 타깃으로 전달한다. 파일 기반 추론에서 데모와 로그 뷰어는 생략할 수 있으나 Vision Apps 런타임과 호환 펌웨어는 필요하다. 근거는 Part 1 A–B다.
- **확인됨** — Vision Apps RTOS 기본 소스에는 **MCU2_0이 마스터인 다중 코어 시작 동기화**가 있다. MAIN R5F와 C66x는 단일 TIDL 노드의 연산 경로에 등장하지 않지만, 배송 빌드를 활용할 때는 초기화 의존성으로 취급한다. C71x 단독 구성이 목표라면 양쪽 IPC 구성 및 RTOS 동기화 정책을 함께 바꾸는 별도 검증이 필요하다. 근거는 Part 1 B다.
- **확인됨** — SDK 동봉 BBAI64 기본 DTB의 C71x 로드 영역은 `0xa8100000`에서 시작하고 배송 Vision Apps ELF는 `0xb2100000`에서 시작한다. **권장 기본안**은 기존 Debian 및 BBAI64 보드 설정을 유지하고, 격리된 부팅 매체에서 배송 펌웨어에 맞는 DT와 런타임을 검증하는 것이다. 첫 포팅에서 펌웨어 재배치와 코어 축소를 동시에 진행하면 원인 분리가 어려워진다. 근거는 Part 1 C–E다.

## Part 1. 알아낸 점

기존 [사전 분석](psdk-porting-preanalysis-ko.md)의 DT 표를 재사용하고, 이번 목표에 맞춰 EP의 실제 동적 의존성과 배송 구성의 코어 동기화를 추가 검증했다. 이하 SDK 상대 경로의 기준은 `sdk_original/`이다. Linux ELF와 DTB는 `tisdk-adas-image-j721e-evm.tar.xz`에서 필요한 멤버만 임시 디렉터리에 추출해 정적으로 검사했다. 대상 Debian의 부팅 DT와 커널 소스·설정은 확보되지 않았다.

### A. ONNX EP에서 C71x까지

```text
TI ONNX Runtime 1.15.0 / TIDLExecutionProvider
  → libtidl_onnxrt_EP: 아티팩트 로드, 서브그래프 생성·실행
  → dlopen(libvx_tidl_rt.so), dlsym(TIDLRT_create / TIDLRT_invoke)
  → TIDL-RT: appInit → appCommonInit (메모리·IPC) → tivxInit / tivxHostInit
  → OpenVX context / TIDL kernel / graph / C7x target
  → TIOVX IPC 알림 + 공유 object descriptor 및 텐서
  → C71x 등록 타깃: tivxKernelTIDLCreate / Process → TIDL 엔진 / MMA
```

| 확인된 연결 | 소스 근거 |
|---|---|
| EP의 서브그래프 초기화·실행 | `c7x-mma-tidl/arm-tidl/onnxrt_ep/src/onnxrt_ep.cpp:50,312,329`의 `dlopen`, `TIDL_subgraphRtCreate`, `TIDL_subgraphRtInvoke`. `common/tidl_runtimes_infer_common.cpp:333,366`과 `common/tidl_onnxrt_common.cpp:234`에서 런타임 함수 포인터를 해석·호출한다. |
| EP의 간접 TIOVX 의존성 | 같은 트리의 `rt/src/tidl_rt_ovx.c:480,656,696,1528,2429,2501,2571,2617`에서 create/init/context/kernel 로드, 노드 생성, 타깃 선택, 그래프 verify/process를 확인했다. `tidlrt_ep/src/tidlrt_ep.cpp`도 native EP의 별도 진입점에서 같은 TIDL-RT API를 쓴다. |
| 호스트 초기화 | `rt/src/armv8/tidl_rt_linux_arm.c:123`의 `tidl_rt_ovx_Init`이 `appInit`을 호출한다. `vision_apps/utils/app_init/src/app_init.c:92`는 공통 초기화 성공 후 TIOVX를 초기화한다. `vision_apps/platform/j721e/linux/app_init.c:175,183,226,232`에서 allocator, CPU 목록과 공유 descriptor, IPC 초기화를 설정한다. `SKIP_TIOVX_INIT`은 이미 초기화를 수행한 호출자용 경로이므로 독립 EP 실행의 의존성을 제거하지 않는다. |
| 원격 실행 | `tiovx/source/platform/board/common/tivx_ipc.c`는 `appIpcSendNotify[Port]`를 호출한다. `app_utils/utils/ipc/src/app_ipc_linux_rpmsg_char.c:362`는 C71x 논리 CPU를 TI RPMsg ID로 매핑하고 endpoint를 연다. `tiovx_kernels/tidl/dsp/vx_tidl_target.c:1413`의 등록 함수는 C7x 타깃 이름에 Create/Process/Delete/Control 콜백을 연결한다. |

### B. Vision Apps와 최소 구성

**확인됨** — 동봉 `usr/lib/firmware/j7-c71_0-fw`의 Vision Apps 대상은 `vision_apps_evm/vx_app_rtos_linux_c7x_1.out`이다. 이미지 ELF에서 TIDL 처리 문자열과 RPMsg 리소스 테이블을 확인했다. `vision_apps/platform/j721e/rtos/c7x_1/{concerto.mak,main.c}` 및 `rtos/common/app_init.c`는 이 구성의 빌드와 초기화를 설명한다. C7x에서 MMU와 CLEC을 설정하고, 메모리 및 IPC를 초기화한 뒤 TIOVX와 `tivxRegisterTIDLTargetKernels()`를 실행한다. IPC echo ELF는 기본 IPC 시험에 사용할 수 있다.

| 분류 | 최소 구성 또는 조건 | 근거 |
|---|---|---|
| 필수 | TI ONNX Runtime 1.15.0, 대응 `libtidl_onnxrt_EP.so`, J721E에서 생성한 ONNX 서브그래프·네트워크·I/O 아티팩트, 파일 기반 실행기 | A절과 [11_02_04_00 태그](https://github.com/TexasInstruments/edgeai-tidl-tools/tree/11_02_04_00) |
| 필수 | `libvx_tidl_rt.so`와 TIOVX/메모리/IPC를 포함한 `libtivision_apps.so.11.2.0`, `libti_rpmsg_char.so.0` 및 동적 링크 의존성 | E절 ELF 검사. 배송 패키지의 SONAME 링크를 함께 유지한다. |
| 필수 | TIDL 타깃을 등록하는 C71x 펌웨어, 대응 DT, K3 remoteproc·RPMsg 및 코어와 A72가 공유하는 메모리 | `rtos/common/app_init.c:722,896`, C절 |
| 조건부 | MAIN R5F0_0(MCU2_0), MAIN R5F0_1(MCU2_1), C66 DSP0/1은 배송 프로파일의 초기화 피어로 취급한다. 특히 MCU2_0은 Linux 호스트 구성의 RTOS 동기화 마스터다. | `rtos/common/app_cfg.h:69–81`가 네 피어를 활성화하고, `app_init.c:574–612`에서 해당 목록으로 `appLogCpuSyncInit`을 호출한다. `app_utils/utils/console_io/src/app_log_writer.c:329–369`는 피어 상태를 기다리는 루프를 포함한다. Linux의 `app_ipc_linux.c:376–409`는 활성 피어의 endpoint 개설 실패를 오류로 처리한다. |
| 불필요 | 파일 기반 ONNX 검증에는 Vision Apps 카메라·스테레오·PTK 데이터와 데모, DLR Python, TFLite delegate, native TIDL Python 바인딩 및 백그라운드 로그 뷰어가 필요 없다. | `vision_apps/apps/basic_demos/app_linux_fs_files/vision_apps_init.sh`는 데이터/라이브러리 경로를 설정하고 로그 뷰어를 시작한다. EP의 필수 초기화는 A절의 프로세스 내부 경로다. 디버그 시 로그는 수집 가치가 있다. |
| 미확인 | 배송 ELF의 모든 조건부 매크로와 대상에서의 최소 활성 피어 집합. 별도 패키지로 제외 가능한 디스플레이 코드와 배송 DSO의 링크 요구도 구분해야 한다. | RTOS 기본 소스의 동기화와 ELF의 TIDL 탑재 근거는 확인했다. 정확한 빌드 매니페스트·링크 맵과 보드의 시작 로그가 필요하다. |

배송 구성을 활용한 첫 실험에서는 다중 코어 초기화 계약을 보존하고 Linux 데모 파일만 줄이는 것이 현실적이다. 이후 C71x 전용 구성에서는 A72/RTOS CPU 목록, MCU2_0 마스터에 의존하는 시작 장벽, 공유 로그·descriptor 초기화 주체와 보드 서비스 소유권을 함께 재검토한다. 코어별 펌웨어의 기동 여부와 연산 배치는 별개의 검증 항목이다.

<a id="section-06"></a>

### C. Device Tree 및 펌웨어

아래는 SDK 이미지의 `boot/dtb/ti/k3-j721e-beagleboneai64.dtb`와 `k3-j721e-vision-apps.dtbo`의 phandle 순서다. 각 쌍은 `[0] DMA / [1] 펌웨어` 시작 주소이며 오버레이의 대상은 `__fixups__`로 식별했다. 대상 Debian의 실제 DT와는 별도로 취급한다. [공개 v6.18 BBAI64 DTS](https://github.com/torvalds/linux/blob/v6.18/arch/arm64/boot/dts/ti/k3-j721e-beagleboneai64.dts)

| 코어 | 기본 DTB | Vision Apps DTBO | 배송 ELF의 .resource_table |
|---|---|---|---|
| C71x | `a8000000 / a8100000` | `b2000000 / b2100000` | `b2100000` |
| C66 DSP0 | `a6000000 / a6100000` | `a9000000 / a8100000` | `a8100000` |
| C66 DSP1 | `a7000000 / a7100000` | `a8000000 / a9100000` | `a9100000` |
| MAIN R5F0_0 | `a2000000 / a2100000` | `a2000000 / a2100000` 및 ETHFW 참조 2개 | `a2100000` |
| MAIN R5F0_1 | `a3000000 / a3100000` | `a4000000 / a4100000` | `a4100000` |
| MAIN R5F1_0/1 | `a4000000 / a4100000`, `a5000000 / a5100000` | `a6000000 / a6100000`, `a7000000 / a7100000` | 해당 배송 ELF 별도 확인 |
| MCU R5F0_0/1 | `a0000000 / a0100000`, `a1000000 / a1100000` | 동일 | 실제 boot/attach 방식 확인 |

- **확인됨** — C71x의 `PT_LOAD` 14개에서 `p_paddr + p_memsz` 기준 DDR 포락 범위는 `[0xb2100000,0xb2ec0726)`이다. SDK Vision Apps carveout `[0xb2100000,0xb8000000)`에 포함된다. 기본 BBAI64 carveout은 `[0xa8100000,0xa9000000)`다. C71x의 RPMsg 리소스는 vring 2개, DA 동적 할당 `0xffffffff`, 정렬 4 KiB, descriptor 각 256개를 요청한다. 근거는 이미지의 `vx_app_rtos_linux_c7x_1.out`에 대한 `readelf -lW -x .resource_table`이다.
- **확인됨** — 공유 메모리는 코어별 1 MiB vring DMA 풀 외에 IPC `[aa000000,ac000000)`, Vision Apps 메모리 `[ac000000,b2000000)`(로그 `ac000000`, object descriptor `ac040000`), DMA heap `[b8000000,d8000000)`, 코어 heap을 포함한다. C71x의 high scratch/heap은 `main.c`의 MMU 식과 `app_mem_map.h`에 따라 VA `0x100000000` 기준을 PA `0x880000000`으로 변환한다. 로드 세그먼트만 검사하면 이러한 런타임 영역을 놓친다. 근거는 `vision_apps/platform/j721e/rtos/{k3-j721e-rtos-memory-map.dtsi,app_mem_map.h,c7x_1/main.c}`다.
- **가능성 높음** — 배송 펌웨어 재사용의 최소 DT 변경은 필요한 코어의 참조, 기존 충돌 carveout 비활성화, 공유 IPC/descriptor/heap 및 의존 피어의 예약 영역 통합이다. R5F0_0의 기본 펌웨어 공간은 15 MiB, Vision Apps는 31 MiB이며 배송 ELF는 `0xa4000000` 경계까지 로드한다. 따라서 C71x만 주소를 교체하고 배송 R5F를 동시에 활성화할 수 없다. Ethernet 큐·버퍼 참조의 필요 여부는 해당 MCU2_0 이미지의 ETHFW 기능과 자원 소유권으로 결정한다. EVM 오버레이의 보드 전용 fragment는 대상 심볼과 기존 장치에 미치는 영향을 검토한다.
- **미확인** — 실제 DT의 모든 활성 예약 영역과 부트로더 예약, CMA 위치, R5F split/lockstep과 TCM, DSP DMA 주소 범위, 고주소 heap의 접근권 및 서명 변형. 대상 DTB·DTBO, 적용 순서, live FDT와 해당 커널 드라이버가 필요하다. 정적 검사 시 보드 DTS·SoC include와 병합 DT를 확보해 64비트 주소, phandle 순서 및 코어별 로드 범위를 함께 검사한다.

<a id="section-07"></a>

### D. Linux 6.18 인터페이스

| 구분 | 확인 범위 및 포팅 대상 |
|---|---|
| 표준 Linux 기능만으로 사용 가능 | remoteproc/virtio RPMsg, RPMsg character endpoint, DMA-BUF fd 공유·동기화 및 DMA heap의 기본 UAPI는 일반 Linux 경로다. J721E에서는 K3 DSP/R5 드라이버와 TI SCI/mailbox/power/reset 결합이 필요하다. 동봉 6.12.57-ti 모듈 `ti_k3_{dsp,r5}_remoteproc.ko`의 ELF에서 `devm_rproc_add` 및 `devm_ti_sci_get_by_phandle` 참조를 확인했다. [Linux remoteproc 문서](https://docs.kernel.org/staging/remoteproc.html), [Linux DMA-BUF 문서](https://docs.kernel.org/driver-api/dma-buf.html) |
| TI 전용 드라이버 또는 패치가 필요할 가능성 | 배송 `libtivision_apps.so`에서 `/dev/dma_heap/carveout_vision_apps_shared-memories`, `/dev/remoteproc0`, `/dev/mem` 문자열을 확인했다. `app_utils/utils/mem/src/app_mem_linux_dma_heap.c`는 heap 할당, `DMA_BUF_IOCTL_SYNC`, `RPROC_IOC_DMA_BUF_ATTACH` 주소 조회와 물리 메모리 매핑 경로를 갖는다. ioctl의 구조체 계약은 `app_utils/utils/mem/include/linux/dma_buf_phys.h`에 있다. 일반 heap/CMA로 fd를 얻는 것과 TI 주소 조회 계약을 만족하는 것은 별개다. 누락 시 `drivers/dma-buf/heaps/`의 carveout exporter와 DT 바인딩, `drivers/remoteproc/remoteproc_cdev.c` 및 대응 UAPI·DMA-BUF 매핑 헬퍼를 비교한다. 보완 범위는 누락이 증명된 기능으로 한정하거나 A72 allocator/주소 매핑 방식을 함께 이식한다. [TI carveout heap 이력](https://git.ti.com/cgit/ti-linux-kernel/ti-linux-kernel/commit/?id=f22103162c771ddd47372b579682445e6dc8dd0e) |
| 실제 커널 설정 및 보드에서 추가 확인 필요 | `CONFIG_REMOTEPROC`, K3 R5/DSP, mailbox, TI SCI, RPMsg virtio/char, DMA-BUF heaps, CMA, devmem 정책과 장치 권한을 확인한다. `remoteproc0`의 실제 이름과 ioctl 지원, heap 노드명, 주소 및 캐시 일관성을 각각 검증한다. SDK 6.12.57-ti 정확한 소스와 대상 6.18 브랜치의 구현을 줄 단위로 확보하지 못했다. 6.18 커널 버전만으로 TI 기능의 존재·부재를 판정할 수 없다. |

<a id="section-08"></a>

### E. AArch64 바이너리 재사용 판정

**확인됨** — 아래는 동봉 이미지에서 `readelf -h -d -V -Ws`로 확인한 AArch64 ELF다. 심볼 버전은 파일별 확인된 최고 요구값이다.

| 이미지의 라이브러리 | GLIBC / GLIBCXX | 링크 및 로딩 특성 |
|---|---|---|
| `usr/lib/libonnxruntime.so.1.15.0`, Python 3.12의 `onnxruntime_pybind11_state.so` | `2.38 / 3.4.29` | `RUNPATH=$ORIGIN`. ORT C++와 Python 배포 파일을 구분한다. Python 패키지의 `__init__.py`도 1.15.0이다. |
| `usr/lib/libtidl_onnxrt_EP.so.1.0` | `2.38 / 3.4.32` | RPATH/RUNPATH 없음. 직접 NEEDED는 표준 C/C++ 런타임 계열이며 실제 TIDL-RT 연결은 `dlopen`이다. |
| `usr/lib/libvx_tidl_rt.so.1.0` | `2.17 / 3.4.32` | RPATH/RUNPATH 없음. `libtivision_apps.so.11.2.0`과 `libti_rpmsg_char.so.0`을 직접 요구하고 `TIDLRT_create`를 내보낸다. |
| `usr/lib/libtivision_apps.so.11.2.0` | `2.38 / 3.4.32` | RPATH/RUNPATH 없음. `appInit`, `appCommonInit`, `tivxInit`, `appMemInit`, `appIpcInit`을 내보낸다. `libti_rpmsg_char.so.0`과 `libEGL.so.1`, `libGLESv2.so.2`, `libgbm.so.1`을 직접 요구한다. 배송 DSO 재사용 시 파일 기반 실행에도 로더가 이 의존성을 해석해야 한다. |
| `usr/lib/libti_rpmsg_char.so.0.6.10` | `2.33 / 해당 없음` | SONAME `libti_rpmsg_char.so.0`, 직접 의존은 libc, RPATH/RUNPATH 없음. |

**가능성 높음** — ABI 호환 시 배송 DSO를 프로세스별 라이브러리 경로에 두고 재사용한다. 우선 C++ ORT로 Python 확장 ABI 변수를 줄인다. Python을 쓰면 공급된 3.12 빌드와 Debian의 실제 Python ABI를 대조한다. GLIBC/GLIBCXX뿐 아니라 모든 NEEDED, SONAME 링크, `dlopen` 경로, TI ORT EP 등록 및 런타임 옵션, 실제 공유 메모리 인터페이스를 검증한다. 일반 ORT와 TI EP를 임의 조합하면 공급자 ABI를 검증할 수 없다. 실패 범위에 따라 **Python 바인딩만**, **TI ORT+EP**, 또는 **TIDL-RT+Vision Apps/TIOVX/app_utils 및 rpmsg-char**를 동일 헤더와 Debian sysroot로 소스 빌드한다. 호스트 ABI 문제만 확인된 경우 RTOS 재빌드는 별도 결정으로 남긴다.

## Part 2. 사용자가 선택할 수 있는 부분

| 선택지 | 수정 범위 | 장점 | 단점·위험 | 권장안과 시점 |
|---|---|---|---|---|
| **A. 배송 Vision Apps ELF + BBAI64 DT 통합** | 보드 DT의 예약 메모리·remoteproc 참조 및 필요한 커널 기능. 배송 초기화 피어 유지 | 검증된 ELF·링커·MMU 계약 활용 | RAM 예약 증가, 기존 코어·ETHFW·보드 자원 충돌 | **우선 경로.** 적용 DT와 부트 기준선 확보 후 변경 승인 |
| **B. 기존 BBAI64 주소에 맞춘 펌웨어 재빌드** | 메모리 생성기, linker/MMU, 공유 영역과 IPC 설정, 필요한 A72/RTOS 빌드. 기존 기본 맵만으로 공유 영역 수용 가능 여부도 계산 | 기존 코어 배치를 최대한 유지하고 피어 축소 가능 | 코드·데이터 정렬 및 heap/IPC 계약을 다시 검증해야 함 | A의 충돌이 풀리지 않거나 메모리 제약이 입증된 뒤 결정 |
| Debian 6.18 유지 / TI 커널 참조 실험 | Debian 경로는 누락된 UAPI만 포팅. 대안은 BBAI64용 테스트 부팅 항목에 TI 계열 커널 준비 | 기존 운영환경 보존 / SDK 동작 기준 확보 | TI 참조 커널도 BBAI64 보드 DT와 부트 지원 검증 필요 | Debian 우선. 커널 소스 비교와 인터페이스 검증 후 대안 결정 |
| 배송 DSO / 소스 빌드 | 격리 경로에 DSO 구성 / 필요한 모듈만 Debian용 재빌드 | 검증 범위 축소 / 호스트 ABI와 불필요한 링크 의존성 제어 | 배송 라이브러리의 간접 ABI / 소스와 툴체인 정합 | 배송 DSO 우선. 실제 로딩 오류 또는 ABI 불일치가 발생하면 빌드 범위 확정 |
| 전체 데모 / 최소 사용자 공간 | 전체 데모 설치 / EP와 필수 DSO·아티팩트만 | 공급사 데모 비교 / 설치 및 디버깅 변수 감소 | 전체 설치의 부수 변경 / 배송 펌웨어 피어와 런타임 의존성은 계속 필요 | **최소 사용자 공간**을 기본으로 결정. 단독 C71x 축소는 오프로딩 검증 후 |

## Part 3. 향후 필요한 작업

아래는 후속 구현에서 실행할 순서다. 각 단계의 권한은 사용자 구현 지시 범위에 따른다.

| 단계와 목표 | 수정 대상·명령 유형 및 산출물 | 검증·성공 기준 | 실패 시 대안·복구 | 승인 |
|---|---|---|---|---|
| 1. 오프라인 기준 고정 | 별도 작업 폴더에서 `readelf`, `sha256sum`, 아카이브 조회로 DSO/ELF/DT/Tools 버전 목록과 단일 파일 입력 모델 후보 정리 | SDK·도구·ORT와 서명 변형 출처 및 체크섬을 재현 가능하게 기록 | 누락된 호스트 도구 번들의 J721E/태그 식별부터 해결 | 로컬 읽기 전용 준비는 추가 승인 불필요 |
| 2. 첫 SSH에서 환경 조사 | 보드 변경 없이 `uname`, `cat`, `readlink`, `ls`, 커널 로그 조회. 아래 목록으로 기준선 기록 | 실제 커널 소스·설정·적용 DT와 코어별 상태 식별 | 권한 부족 시 해당 읽기 항목을 사용자에게 요청하거나 UART 로그 사용 | **SSH 별도 승인** |
| 3. 복구 경로와 DT/ELF 정합 | 테스트 SD·원본 부트 항목을 준비. 별도 작업 디렉터리에서 DTS 편집·DTB 빌드 및 오프라인 병합, phandle·메모리 검사 | 원본으로 부팅 복귀 가능, 중복 0건, 코어별 로드 범위·공유 주소 일치 | 충돌 원인별 DT 조정. 배치 보존 불가 시 전략 B 검토 | **DT 변경·빌드 및 테스트 매체 쓰기 승인** |
| 4. 커널과 펌웨어 초기화 | 필요 시 검증된 커널 기능만 별도 빌드. 테스트 부트 항목에 정합 DT와 펌웨어 세트를 함께 배치. remoteproc·RPMsg·DMA heap 및 공유 버퍼 검사 | 필수 피어 동기화 완료, endpoint 생성, 양방향 버퍼 데이터·캐시 정합, 오류 없는 반복 할당 | 첫 실패가 로더/전원/IPC/heap 중 어디인지 로그로 분리. DT·펌웨어·커널을 동일 기준선으로 함께 복귀 | **빌드·커널 변경·펌웨어 배치·재부팅 승인** |
| 5. EP 실행 | 테스트 경로에서 DSO 로딩 및 provider 등록 확인. 호스트에서 J721E Tools로 단일 모델 컴파일. TI ORT로 동일 파일 입력 CPU 기준과 TIDL 경로 실행 | 출력이 사전 정의 허용오차 안에 있고, 실제 위임 서브그래프 1개 이상과 C71x/TIDL 성능 카운터 또는 펌웨어 실행 로그가 관찰됨 | provider/ABI, 아티팩트 형식, IPC 오류를 분리. CPU-only 성공은 오프로딩 미통과로 기록 | **도구 설치·빌드·보드 실행은 후속 구현 승인 범위** |
| 6. 재현성 검증 | 콜드부트 및 반복 실행, 버전·해시·입출력·로그·복구 절차 문서화 | 새 테스트 환경에서 재현되고 기존 부팅 경로 복귀 확인 | 실패 단계부터 원인 보정 후 재검증 | 테스트 매체 재설치·재부팅은 승인 범위 내 |

### 첫 SSH 세션의 읽기 전용 조사 목록

- OS·ABI와 부팅 출처 — `/etc/os-release`, `uname -a`, 패키지 및 라이브러리 버전, Python 버전, 부트 매체, 커널 패키지·설정·소스 리비전. SPL/U-Boot와 TIFS/DM은 UART 버전·ABI 로그로 보완한다.
- DT와 메모리 — `/sys/firmware/fdt` 또는 live DT, 부트 설정과 실제 DTB/DTBO, `/proc/iomem`, 부팅 로그의 reserved-memory/CMA를 확보한다. 코어 `status`, `firmware-name`, `memory-region`, R5F cluster mode, `ranges`와 `dma-ranges`를 추출한다.
- Remoteproc·RPMsg·DMA — `/sys/class/remoteproc/remoteproc*/{name,state,firmware}`, 펌웨어 링크와 체크섬, `/sys/bus/rpmsg/devices`, `/dev/rpmsg*`, `/dev/remoteproc*`, `/dev/dma_heap/` 목록과 권한을 확보한다. 첫 조사에서는 코어 상태 쓰기, ioctl 시험 및 모듈 로드를 보류한다.

## Final Recommendation

1. **현재 착수 가능 여부 — CONDITIONAL GO.** 오프라인 준비부터 진행한다. 실제 보드 변경은 적용 DT·커널 기능·복구 경로가 확인된 뒤 시작한다.
2. **권장 전략** — Debian과 BBAI64 부트 체인을 보존하고, 테스트 SD에서 **전략 A + 배송 DSO + 최소 ONNX 실행기**를 적용한다. 배송 RTOS 피어 구성을 먼저 검증한다.
3. **착수 전 필수 확인** — 적용 DT와 코어 소유권, GP/HS 및 펌웨어 변형, TI heap/ioctl의 실제 지원, 호스트 ABI·SONAME, 롤백 가능한 테스트 부팅이다.
4. **지금 필요한 사용자 선택** — 실제 구현 단계에서는 SSH 읽기 전용 조사 범위와 테스트 SD 변경 범위를 정한다. 펌웨어 재빌드와 커널 전환은 첫 검증 결과가 나오면 판단한다.
5. **바로 가능한 준비** — SDK 내부 구성의 해시·SONAME 목록 정리, 대상 커널 소스/DT 확인 항목 준비, 모델·입력·CPU 기준 출력의 검증 형식 작성, 오프라인 DT/ELF 검사 항목 정의다.

이번 단계에서는 정적 분석과 보고서 작성만 수행했다.
