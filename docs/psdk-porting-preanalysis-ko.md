# BBAI64 PSDK 11.02 포팅 사전 분석

## 1. Executive Summary

- **확인됨** — TI가 J721E에서 TIDL Tools **11_02_04_00**의 기본 조합으로 명시한 버전은 **PSDK Linux 11.02.00.04 + PSDK RTOS 11.02.00.06**이다. 로컬 SDK는 이 RTOS 릴리스와 대응하는 ADAS Linux 이미지를 포함한다. 요청한 **11.02.00.07**의 J721E 제품 식별 및 동일 Tools 조합은 **미확인**이다. 먼저 정확한 패키지명이나 TI 다운로드 식별자를 확보한다. [TI 호환성 표](https://github.com/TexasInstruments/edgeai-tidl-tools/blob/master/docs/sdk_version_compatibility_table.md#sdk-version-110200xx)
- **확인됨** — 동봉 BBAI64 기본 DTB와 Vision Apps 펌웨어의 DDR 배치는 다르다. 예를 들어 기본 C71x 펌웨어 영역은 `0xa8100000`부터 시작하고 Vision Apps C71x ELF의 리소스 테이블과 첫 로드 세그먼트는 `0xb2100000`에 있다. 기본 DTB로 Vision Apps 펌웨어를 교체하는 방식은 정적 DDR 매핑 검사에서 탈락한다. 근거는 §4–5의 DTB phandle과 ELF 비교다.
- **가능성 높음** — 기존 Debian을 유지하는 경로의 주요 과제는 BBAI64 전용 DT 통합과 TI 공유 메모리 커널 인터페이스의 이식이다. AArch64 런타임은 ABI 검사 후 재사용할 수 있다. 실기에서는 보드 부팅을 유지한 상태에서 remoteproc·RPMsg, 공유 버퍼, C71x/MMA 추론 순으로 검증한다. 근거는 §3, §6, 통과 기준은 §8이다.

## 2. 분석 범위 및 SDK 버전 검증

경로는 특별한 표기가 없으면 `sdk_original/` 기준이다. 이미지 내부 경로는 `tisdk-adas-image-j721e-evm.tar.xz`에서 확인했다. 두 아카이브를 읽고 필요한 멤버만 임시 디렉터리에서 정적 검사했다. 보드 접근, 설치, 빌드, SDK 및 시스템 파일 변경은 수행하지 않았다.

| 판단 | 항목 | 근거 |
|---|---|---|
| 확인됨 | 로컬 제품은 TI Processor SDK RTOS for J721E EVM 11.02.00.06 계열이다. A72용 ADAS Linux 루트 파일시스템과 부트 아카이브를 동봉한다. | 링크 대상 `ti-processor-sdk-rtos-j721e-evm-11_02_00_06`, `psdk_rtos/PROCESSOR_SDK_RTOS_release_notes.html`, `psdk_rtos/docs/user_guide/_sources/release_notes_11_02_00_j721e.rst.txt`, `sdk_builder/tools_path.mak:89` |
| 확인됨 | 로컬 RTOS 구성의 Linux SDK 참조는 `ti-processor-sdk-linux-adas-j721e-evm-11_02_00_04`이다. | `sdk_builder/tools_path.mak:89`, [TI TVM 설치 문서의 PSDK 버전 표](https://software-dl.ti.com/codegen/docs/tvm/tvm_tidl_users_guide/getting-started/installation.html#processor-sdk-versions) |
| 확인됨 | TIDL Tools 11_02_04_00은 위 J721E 조합의 기본 릴리스다. | [TI 호환성 표](https://github.com/TexasInstruments/edgeai-tidl-tools/blob/master/docs/sdk_version_compatibility_table.md#sdk-version-110200xx), [11_02_04_00 릴리스](https://github.com/TexasInstruments/edgeai-tidl-tools/releases/tag/11_02_04_00) |
| 미확인 | 11.02.00.07의 정확한 제품명, J721E 대상 배포 여부 및 Tools 호환성. TI 저장소에는 11.02.00.07을 포함하는 소스 태그가 보이며, 매니페스트 로그의 Analytics .07 변경은 J722S로 표기된다. DM 펌웨어 태그도 별도로 존재한다. | [TI 매니페스트 로그](https://git.ti.com/cgit/processor-sdk/psdk_repo_manifests/log/), [TI PDK Sciclient 로그](https://git.ti.com/cgit/processor-sdk/pdk/log/packages/ti/drv/sciclient/soc). 필요한 자료는 .07 J721E 제품의 다운로드 페이지, 매니페스트, 호환성 릴리스 노트다. |
| 미확인 | 독립 호스트 도구 11_02_04_00의 로컬 설치 상태. `c7x-mma-tidl/tidl_tools/`에서 `tidl_model_import.so` 등 끊어진 링크를 확인했다. | 태그에 대응하는 J721E 호스트 번들의 `versions.txt`, 실제 파일 및 체크섬을 확보한다. |

## 3. PSDK 구성 요소 및 의존성

| 항목 | 확인된 기준 및 파일 | 포팅 판단 |
|---|---|---|
| Linux | 동봉 이미지 `usr/lib/modules/6.12.57-ti-01343-g15b58b1dcd0e-dirty/`, `usr/lib/os-release`의 Arago 2025.01 | **확인됨** — 동봉 기준이다. Debian 13 / 6.18에 대한 TI 검증 근거는 **미확인**이다. |
| 부트로더 | `boot-adas-j721e-evm.tar.gz`의 `tiboot3-…-2025.01+git97423+df1fe23-…bin`, `tispl.bin`, `u-boot.img`, `uEnv.txt`. 아카이브 `version`은 `20260123_adas` | **확인됨** — EVM U-Boot 2025.01 계열 패키징이다. **가능성 높음** — BBAI64 기존 부트 체인을 우선 유지한다. 보드 부팅, TI SCI 및 코어 제어가 통과 기준이다. |
| System Firmware | 부트 아카이브의 `sysfw.itb` 및 GP/HS 변형. PDK의 `packages/ti/drv/sciclient/`에서 TI SCI 및 보드 구성 제공 | **미확인** — 동봉 TIFS/DM의 정확한 내부 버전 및 대상 보드와의 ABI. FIT 구성·펌웨어 메타데이터, 부트 콘솔의 TIFS/DM 버전·ABI 및 TI SCI 자원 할당을 확인한다. |
| 설치·빌드 진입점 | `sdk_builder/scripts/setup_psdk_rtos.sh`, `sdk_builder/tools_path.mak`, `vision_apps/apps/basic_demos/app_linux_fs_files/vision_apps_init.sh`, `vision_apps_evm/run_app_tidl.sh`(같은 디렉터리 아래) | **확인됨** — SDK 환경 및 데모의 참조 자료다. 실제 포팅에서는 하드코딩 경로, 서비스와 펌웨어 링크, 커널 장치 의존성을 먼저 검토한다. |
| TIOVX/Vision Apps | `tiovx/include/TI/`, `vision_apps/platform/j721e/linux/app_init.c`, `vision_apps/platform/j721e/rtos/app_mem_map.h`, `app_utils/utils/mem/src/app_mem_linux_dma_heap.c` | **확인됨** — A72 초기화 코드, RTOS 메모리 계약과 Linux 공유 버퍼 구현이 분리돼 있다. A72와 원격 코어의 IPC·공유 메모리 계약을 함께 맞춘다. |
| TIDL/MMA 및 IPC | `c7x-mma-tidl/arm-tidl/`, `mmalib_11_02_00_06/`, `pdk_jacinto_11_02_00_15/packages/ti/drv/ipc/`, 이미지의 `usr/lib/firmware/{ti-ipc/j721e,vision_apps_evm}/` | **확인됨** — Linux용 EP, C7x/MMA 구성 요소, RTOS IPC와 두 종류의 코어 펌웨어가 있다. |

## 4. BBAI64와 PSDK의 DTS 비교

**확인됨** — 실제 대상 Debian의 DTS/DTB는 제공되지 않았다. 아래 비교의 BBAI64 열은 동봉 Linux 이미지의 `boot/dtb/ti/k3-j721e-beagleboneai64.dtb`다. EVM 열은 같은 위치의 `k3-j721e-common-proc-board.dtb`와 `k3-j721e-vision-apps.dtbo`를 사용했다. 기본 DTB의 phandle과 DTBO의 `__fixups__`, `__local_fixups__`를 읽어 대상을 확인했다. [공개 Linux v6.18 BBAI64 DTS](https://github.com/torvalds/linux/blob/v6.18/arch/arm64/boot/dts/ti/k3-j721e-beagleboneai64.dts)는 대상 보드의 실제 커널 소스 확인 시 비교 기준으로 쓴다.

각 쌍은 `memory-region[0] DMA 시작 → [1] 펌웨어 시작`이다. DMA는 모두 1 MiB다. 펌웨어 끝 주소는 미포함이다.

| 노드 / `firmware-name` | BBAI64 기본 쌍 / 끝 | EVM Vision Apps 쌍 / 끝 |
|---|---|---|
| MCU R5F0_0 / `j7-mcu-r5f0_0-fw` | `a0000000 → a0100000 / a1000000` | 동일 |
| MCU R5F0_1 / `j7-mcu-r5f0_1-fw` | `a1000000 → a1100000 / a2000000` | 동일 |
| MAIN R5F0_0 / `j7-main-r5f0_0-fw` | `a2000000 → a2100000 / a3000000` | `a2000000 → a2100000 / a4000000` |
| MAIN R5F0_1 / `j7-main-r5f0_1-fw` | `a3000000 → a3100000 / a4000000` | `a4000000 → a4100000 / a6000000` |
| MAIN R5F1_0 / `j7-main-r5f1_0-fw` | `a4000000 → a4100000 / a5000000` | `a6000000 → a6100000 / a7000000` |
| MAIN R5F1_1 / `j7-main-r5f1_1-fw` | `a5000000 → a5100000 / a6000000` | `a7000000 → a7100000 / a8000000` |
| DSP0 `dsp@4d80800000` / `j7-c66_0-fw` | `a6000000 → a6100000 / a7000000` | `a9000000 → a8100000 / a9000000` |
| DSP1 `dsp@4d81800000` / `j7-c66_1-fw` | `a7000000 → a7100000 / a8000000` | `a8000000 → a9100000 / aa000000` |
| C71x `dsp@64800000` / `j7-c71_0-fw` | `a8000000 → a8100000 / a9000000` | `b2000000 → b2100000 / b8000000` |

- **확인됨** — DSP의 `compatible`은 `ti,j721e-c66-dsp`/ `ti,j721e-c71-dsp`이며 기본 DTB에서 `status = "okay"`다. R5F 코어의 `compatible`은 `ti,j721e-r5f`이고 비교한 기본 DTB의 코어 노드에 명시적 `status`가 없다. 실기에서는 부모 클러스터의 상태와 `ti,cluster-mode`도 확인한다. Vision Apps DTBO는 MAIN R5F0_0의 [2], [3]에 가상 Ethernet 큐·버퍼를 추가한다.
- **확인됨** — 기본 EVM은 C66 DMA가 교차한다. DSP0은 `a7000000 → a6100000`, DSP1은 `a6000000 → a7100000`이다. 동봉 BBAI64는 위 표의 연속 쌍이다. Vision Apps와 Edge AI DTBO는 둘 다 EVM 쪽의 교차 방식으로 재지정한다. 기본 예약 노드를 비활성화하는 fragment도 포함한다. BBAI64에서는 DTBO의 외부 심볼과 부팅 전 병합 결과를 확인한 후 적용 여부를 결정한다.
- **확인됨** — 각 프로파일의 표 안에서 `shared-dma-pool`, `no-map`인 정적 DMA·펌웨어 영역은 서로 겹치지 않고 시작·크기가 MiB 경계에 맞는다. 기본 DTB의 OP-TEE `[0x9e800000,0xa0000000)`과도 겹치지 않는다. 두 프로파일을 동시에 활성화하면 주소 충돌이 생긴다. 예를 들어 Vision Apps MAIN R5F1_0의 DMA와 펌웨어가 BBAI64 기본 DSP0 쌍과 일치한다.

| 추가 영역 | 기본 BBAI64 | SDK Vision Apps 시작–끝 (끝 미포함) |
|---|---|---|
| RTOS IPC | `0xaa000000–0xabc00000` (28 MiB) | `0xaa000000–0xac000000` (32 MiB), `alignment=0x1000`, `no-map` |
| Vision Apps DMA 메모리 | 해당 영역 없음 | `0xac000000–0xb2000000` (96 MiB), `shared-dma-pool`, `no-map` |
| Linux 공유 heap | 해당 영역 없음 | `0xb8000000–0xd8000000` (512 MiB), `dma-heap-carveout` |
| 코어 heap 및 ETHFW | 해당 영역 없음 | low heap `0xd8000000–0xe4000000`, ETH 큐 `0xe4000000–0xe4800000`, 버퍼 `0xe4800000–0xe6000000`, high heap `0x880000000–0x8a7000000`. 모두 `shared-dma-pool`, `no-map`. |

**확인됨** — SDK 정적 목록과 기본 BBAI64의 선언 RAM 뱅크 `[0x80000000,0x100000000)`, `[0x880000000,0x900000000)`의 수치 대조에서는 표의 모든 구간이 뱅크 안에 있다. SDK Vision Apps 정적 구간끼리도 겹치지 않는다. 기본 EVM DTB에는 별도의 동적 `linux,cma`(`shared-dma-pool`, `reusable`)가 있다. **미확인** — 대상의 CMA 실제 위치, 부트로더 추가 예약, DMA 마스크·주소 변환 및 high heap 접근성. 적용 DT의 `/memory`, `/reserved-memory`, 부모 버스 `ranges`·`dma-ranges`, CMA `size`·`alignment`·`alloc-ranges`, 부팅 로그를 확인한다. 근거는 두 기본 DTB와 `vision_apps/platform/j721e/rtos/k3-j721e-rtos-memory-map.dtsi`다.

## 5. Remoteproc, Firmware 및 Memory Map 호환성

**확인됨** — 이미지의 `usr/lib/firmware/j7-*-fw` 링크는 다음 Vision Apps ELF를 가리킨다. `readelf -lW/-SW`의 `PT_LOAD` 물리 주소와 메모리 크기, `.resource_table`을 비교했다. 아래 DDR 구간은 실제 세그먼트의 시작부터 최대 끝까지이며 중간 공백을 포함한다.

| 링크 대상 (`usr/lib/firmware/vision_apps_evm/`) | DDR 로드 범위 / 리소스 테이블 | 정적 판정 |
|---|---|---|
| `vx_app_rtos_linux_c6x_1.out` | `a8100000–a85ea278` / `a8100000` | Vision Apps DSP0 carveout에 포함. BBAI64 기본 DSP0에 불포함. |
| `vx_app_rtos_linux_c6x_2.out` | `a9100000–a95ea278` / `a9100000` | Vision Apps DSP1 carveout에 포함. BBAI64 기본 DSP1에 불포함. |
| `vx_app_rtos_linux_c7x_1.out` | `b2100000–b2ec0726` / `b2100000` | Vision Apps C71x carveout에 포함. BBAI64 기본 C71x에 불포함. |
| `vx_app_rtos_linux_mcu2_0.out` | `a2100000–a4000000` / `a2100000` | 31 MiB Vision Apps MAIN R5F0_0 영역 필요. BBAI64 기본 영역의 끝을 넘는다. |
| `vx_app_rtos_linux_mcu2_1.out` | `a4100000–a6000000` / `a4100000` | Vision Apps MAIN R5F0_1 carveout에 포함. BBAI64 기본 MAIN R5F0_1에 불포함. |

R5F 두 ELF에는 DA `0x0`의 로드 세그먼트도 있다. 해당 구간은 대상 드라이버의 TCM 변환과 클러스터 모드로 검증한다. 이미지의 `-fw-sec` 링크는 서명 변형을 가리킨다. 위 표는 비서명 ELF의 검사 결과이며 대상 SoC 보안 유형과 로더에서 사용할 변형은 **미확인**이다. 근거는 ELF, 링크 및 `vision_apps/platform/j721e/rtos/{c66x_1,c66x_2,c7x_1,mcu2_0,mcu2_1}/linker_mem_map.cmd`다.

- **확인됨** — Vision Apps의 C66 교차 배치는 배송 DTBO가 명시적으로 구성한 것이다. 각 ELF는 해당 코어의 두 번째 phandle에 맞는다. TI DSP 드라이버는 인덱스 0을 vring DMA 풀로 초기화하고 이후 항목을 정적 carveout으로 매핑한다. C71x Vision Apps 리소스 테이블의 RPMsg vdev에는 두 vring이 있고, 각각 DA `0xffffffff`(호스트 할당), 정렬 `0x1000`, 256개 descriptor를 요청한다. 따라서 펌웨어 DDR 배치가 맞는지와 DMA 풀이 올바르게 연결되는지는 각각 검사해야 한다. **미확인** — SDK가 교차 주소를 선택한 설계 이유와 실제 Debian 커널의 해석은 대상 드라이버와 유효 DT가 필요하다. [TI DSP remoteproc 드라이버](https://git.ti.com/cgit/ti-linux-kernel/ti-linux-kernel-next/tree/drivers/remoteproc/ti_k3_dsp_remoteproc.c?id=d37a4165531158223df79c9d5b12bed96699cc89)
- **확인됨** — 이미지 `usr/lib/firmware/ti-ipc/j721e/`의 IPC echo DSP0·DSP1·C71x ELF는 각각 `a6100000`, `a7100000`, `a8100000`에 리소스 테이블을 두며 DDR 로드 범위는 BBAI64 기본 carveout에 포함된다. 이 파일들은 기본 메모리 맵에서 IPC를 분리 검증할 후보다. 실제 Vision Apps 로딩과 런타임은 별도 단계에서 검증한다.
- **미확인** — 적용 DT에서 R5F TCM, DSP 로컬 RAM, 4 GiB 위 heap의 DA↔PA 변환과 접근 권한. 대상 커널의 K3 R5/DSP `da_to_va` 및 reserved-memory 초기화, 펌웨어 링커 맵·MMU 설정, TI SCI 소유권을 대조한다.

## 6. TIOVX/TIDL Runtime 포팅 요구사항

| 판단 | 구성 요소 및 진행 조건 | 근거 |
|---|---|---|
| 가능성 높음 | A72의 ONNX EP와 native TIDL EP는 Debian에서 바이너리 재사용 후보다. 두 ELF는 AArch64이며 직접 의존성에 `libstdc++.so.6`, `libgcc_s.so.1`, `libm.so.6`, `libc.so.6`가 있다. `GLIBC_2.38`, `GLIBCXX_3.4.32`를 포함한 요구 심볼, 간접 의존성과 실행 시 로드되는 라이브러리를 모두 확인하고 동일 런타임 API로 로딩 시험을 통과해야 한다. | `c7x-mma-tidl/arm-tidl/{onnxrt_ep,tidlrt_ep}/out/J721E/A72/LINUX/release/*.so.1.0`의 `readelf -hdV` |
| 가능성 높음 | Debian 커널의 K3 remoteproc, mailbox, TI SCI power/reset, virtio RPMsg가 필요한 기능을 제공하면 유지한다. DSP/R5 드라이버와 `memory-region` 순서, `mboxes`, `power-domains`, `resets`, TI SCI 핸들, R5 클러스터 모드를 실제 커널의 바인딩으로 대조한다. IPC echo 왕복이 통과 기준이다. | §4 DTB, TI 드라이버, `pdk_jacinto_11_02_00_15/packages/ti/drv/ipc/` |
| 확인됨 | SDK allocator가 `/dev/dma_heap/carveout_vision_apps_shared-memories` 또는 빌드 조건에 따라 `carveout_edgeai_shared-memories`를 연다. `DMA_HEAP_IOCTL_ALLOC`, `DMA_BUF_IOCTL_SYNC`와 물리 주소 조회 경로의 `RPROC_IOC_DMA_BUF_ATTACH`를 확인했다. `/dev/remoteproc0`을 여는 코드도 있다. | `app_utils/utils/mem/src/app_mem_linux_dma_heap.c`의 `DMA_HEAP_NAME`, ioctl 호출 및 `/dev/remoteproc0` |
| 가능성 높음 | Linux 6.18에 필요한 exporter 또는 remoteproc ioctl이 빠졌다면 해당 TI 드라이버를 이식하거나 allocator를 지원 인터페이스로 소스 포팅해야 한다. CMA 크기 확대만으로 heap 이름, ioctl 및 DSP에서 접근 가능한 주소 계약을 충족할 수 없다. fd 할당·공유·주소 확인·양방향 패턴 검증을 통과해야 한다. | 위 allocator, SDK DT의 `compatible = "dma-heap-carveout"`, [TI carveout heap 변경 이력](https://git.ti.com/cgit/ti-linux-kernel/ti-linux-kernel/commit/?id=f22103162c771ddd47372b579682445e6dc8dd0e) |
| 가능성 높음 | Vision Apps ELF는 동일한 메모리 맵과 IPC 계약을 보존할 수 있으면 재사용 후보다. 배치를 바꿔야 하면 DTS와 함께 linker map, `app_mem_map.h`, 코어별 MMU/MPU, 공유 IPC 설정을 소스에서 정합시킨다. | `vision_apps/platform/j721e/rtos/gen_linker_mem_map.py`, `app_mem_map.h`, 코어별 `linker_mem_map.cmd`, §5 ELF |
| 확인됨 | 호스트에서 J721E용 Tools와 선택한 런타임 조합으로 모델을 컴파일하고 타깃에는 대응 라이브러리와 펌웨어를 배치해야 한다. | [TI 태그 고정 README](https://github.com/TexasInstruments/edgeai-tidl-tools/tree/11_02_04_00), [TI 모델 아티팩트 호환성 진단](https://github.com/TexasInstruments/edgeai-tidl-tools/blob/master/docs/debugging.md#model-artifacts-incompatibility) |

## 7. 예상되는 문제와 위험성

| 우선순위 | 판단과 주의 사항 |
|---|---|
| 높음 | **확인됨** — DT와 펌웨어 혼용은 DDR 로딩 충돌을 만든다. 기본 DT의 예약 노드 비활성화와 새 노드의 활성 여부를 병합 DT에서 확인한다. 펌웨어 교체는 DT 변경과 같은 검증 단위로 관리한다. §4–5 |
| 높음 | **가능성 높음** — EVM 오버레이는 BBAI64 DT에 없는 외부 심볼이나 보드별 자원을 참조할 수 있다. 부트 아카이브 `uEnv.txt`는 `k3-j721e-evm-ethfw.dtbo`와 Vision Apps DTBO를 함께 지정한다. BBAI64에서는 필요한 fragment만 이식하고 Ethernet, eMMC, SD, 콘솔의 기존 동작을 재검증한다. |
| 높음 | **미확인** — 기존 부트 체인의 TI SCI 자원 소유권과 HS/GP 펌웨어 선택이 SDK 펌웨어에 맞는지 확인한다. 부트 콘솔, remoteproc 상태 및 첫 오류로 펌웨어 인증·전원·리셋 문제를 분리한다. §3, §5 |
| 높음 | **가능성 높음** — heap이 열려도 물리 주소 조회, 캐시 동기화 또는 DSP 접근에서 실패할 수 있다. `remoteproc0` 인덱스는 보드의 실제 장치 매핑과 대조한다. 공유 버퍼 양방향 데이터와 반복 할당을 검증한 뒤 추론으로 진행한다. §6 |
| 중간 | **가능성 높음** — ABI나 모델 버전 오류와 CPU fallback을 구분해야 한다. EP 등록, 오프로딩된 서브그래프, C7x 실행 프로파일을 함께 확인한다. 출력 정확도와 지연 시간만으로 오프로딩을 판정하지 않는다. §6, §8 |

## 8. 권장 작업 순서 및 단계별 검증 기준

다음은 후속 포팅 절차다. 작업용 SD와 별도 소스 디렉터리에서 진행하고 각 단계의 산출물과 부팅 로그를 보존한다.

| 순서 | 작업 및 주의 사항 | 통과 또는 중단 기준 |
|---|---|---|
| 1. 버전 세트 고정 | J721E .07 제품 근거가 확보되면 그 매니페스트부터 검증한다. 확보 전에는 공식 .04 Linux / .06 RTOS / Tools 11_02_04_00을 참조 기준으로 기록한다. 커널·DT·펌웨어·라이브러리·모델 도구의 태그와 해시를 남긴다. | 실험에 투입할 모든 구성 요소의 출처와 버전 조합이 식별된다. |
| 2. 복구 가능한 기준선 확보 | UART와 작업용 SD로 기존 Debian 부팅 및 원본 부트 항목 복귀를 검증한다. eMMC 및 기존 부트로더를 보존한다. 기본 DT, 실제 적용 DT, 펌웨어 링크와 로그를 수집한다. | 원본 구성에서 부팅·스토리지·네트워크가 재현되고 실패 시 원본 부트 항목으로 돌아갈 수 있다. |
| 3. 기본 Remoteproc/IPC 확인 | 기본 DT에 맞는 기존 펌웨어로 필요한 remoteproc과 RPMsg를 검증한다. IPC echo를 사용할 경우 먼저 §5와 같은 로드 주소·보안 변형 확인을 거친다. 사전 기동 코어와 클러스터 모드를 확인한다. | 대상 코어 이름과 firmware가 일치하고 해당 RPMsg 서비스에서 왕복에 성공한다. 실패 시 mailbox, 전원·리셋, TI SCI, 로드 주소부터 좁힌다. |
| 4. BBAI64용 DT·커널 준비 | 필요한 Vision Apps 예약 영역과 코어 참조를 BBAI64 DT에 적용한다. SDK EVM DTBO의 외부 심볼과 가상 Ethernet 자원 의존성을 검토한다. 누락이 확인된 커널 기능만 포팅한다. 다른 부트 항목을 유지한 채 오프라인 병합 DT와 ELF를 대조한다. | 예약 범위 중복 0건, 모든 phandle 해석 가능, 정적 로드 범위 수용, 필요한 heap과 주소 조회 인터페이스 제공. 하나라도 실패하면 Vision Apps ELF로 부팅하지 않는다. |
| 5. Vision Apps 코어·공유 메모리 확인 | 테스트 부트 항목에서 일치하는 DT·펌웨어 세트를 함께 적용한다. 코어별 기동 후 TIOVX 초기화, 필요한 타깃 등록, IPC 및 DMA-BUF 할당·매핑·주소 조회·캐시 동기화를 검증한다. | RPMsg 및 TIOVX 초기화 성공, CPU/DSP 버퍼 패턴 일치, 반복 실행에서 할당 오류나 remoteproc crash 없음. 실패 시 테스트 DT와 펌웨어를 함께 되돌린다. |
| 6. 최소 TIDL 추론 | 파일 입력의 소형 모델 하나를 고정된 J721E 도구로 컴파일한다. 먼저 한 런타임만 사용하고 모델·입력·전처리·정밀도·비교 허용오차를 기록한다. | 출력이 기준 허용오차 이내이고 EP가 오프로딩한 서브그래프와 C7x/MMA 실행 근거가 관찰된다. CPU 경로의 결과만 확보되면 이 단계는 미통과다. |
| 7. 재현·확장 | 콜드부트와 반복 추론을 검증한 뒤 설치 절차, 파일 목록, 버전·해시, 검증 로그, 복구 절차를 기록한다. 카메라, 디스플레이, ETHFW는 최소 추론 통과 후 필요한 경우 추가한다. | 새 테스트 이미지에서 같은 절차로 추론과 원본 부트 복귀를 재현한다. |

## 9. 실제 보드 접근 후 추가 확인할 사항

- **미확인** — OS와 커널 패키지, 정확한 소스 리비전과 빌드 설정. `/etc/os-release`, `uname -a`, 패키지 버전, `/proc/config.gz` 또는 해당 `/boot/config-*`를 수집한다.
- **미확인** — 부트 체인 및 실제 DT. UART에서 SPL/U-Boot, TIFS/DM 버전과 ABI를 기록한다. 실제 DTB·DTBO와 적용 순서, `/sys/firmware/fdt` 또는 live DT, 부트 설정 파일을 확보한다. DTC 비교에는 BBAI64 DTS와 J721E SoC/main/MCU DTSI, IPC include와 보드 오버레이가 필요하다.
- **미확인** — 코어 및 메모리 상태. `/sys/class/remoteproc/remoteproc*/{name,state,firmware}`, 펌웨어 링크, `/sys/bus/rpmsg/devices`, `/proc/iomem`, 부팅 로그의 reserved-memory/CMA, `/dev/dma_heap/`, `/dev/remoteproc*`를 수집한다. §4의 DSP0/DSP1 DMA 참조가 실기에서 연속인지 교차인지 이 자료로 확정한다.
- **미확인** — Debian에서의 실제 ABI·가속 성능. 라이브러리 버전과 심볼, 런타임 및 펌웨어 빌드 식별자, EP 할당·C7x 프로파일 로그, 모델 정확도, 반복 실행 중 메모리 사용량을 §8 통과 기준과 대조한다.

## 10. 최종 권장안 및 참고 문헌

1. **버전 결정** — 11.02.00.07을 요구하는 제품이나 배포 근거를 먼저 확인한다. 확보 전 포팅의 비교 기준은 TI가 검증한 J721E Linux .04 / RTOS .06 / TIDL Tools 11_02_04_00으로 둔다. [TI SDK 호환성 표](https://github.com/TexasInstruments/edgeai-tidl-tools/blob/master/docs/sdk_version_compatibility_table.md)
2. **Debian 유지 결정** — 기존 부트 체인을 보존한 테스트 SD에서 Linux 6.18의 remoteproc과 공유 DMA-BUF 인터페이스를 우선 확인한다. 누락 기능을 확인한 경우 해당 커널 기능 이식 또는 allocator 소스 포팅의 비용을 산정한다. [TI carveout heap 변경 이력](https://git.ti.com/cgit/ti-linux-kernel/ti-linux-kernel/commit/?id=f22103162c771ddd47372b579682445e6dc8dd0e)
3. **DT·펌웨어 결정** — 동봉 ELF를 재사용할 때는 BBAI64 보드 설정 위에 대응 Vision Apps 메모리 맵을 통합하는 경로를 우선 평가한다. C66 DMA의 직선/교차 배치는 적용 DT와 펌웨어의 계약으로 판단한다. DDR 배치 변경이 필요하면 링커·MMU 설정과 DT를 함께 갱신한다. 근거는 로컬 DTBO, 펌웨어 ELF 및 `vision_apps/platform/j721e/rtos/`의 생성기와 링커 맵이다.
4. **진행 결정** — §8의 기본 IPC와 공유 메모리 검증을 통과한 뒤에만 C71x/MMA 추론을 진행한다. BBAI64 부트 기준은 보드 문서와 실제 부트 콘솔을 사용한다. [BeagleBone AI-64 공식 문서](https://docs.beagleboard.org/boards/beaglebone/ai-64/)
