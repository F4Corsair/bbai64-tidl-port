# r47용 TI DMA 기능 이식 범위

TI Linux 6.12 SDK 이미지의 커널 릴리스 문자열에 포함된 `15b58b1dcd0e`를 공개 TI 저장소에서 `15b58b1dcd0e0a79d83740b81da1a1367f6f3f68`로 확인했다. 이 커밋에 exporter와 remoteproc attach ioctl이 모두 있다. 적용 대상은 BeagleBoard `6.18.39-arm64-k3-r47`의 `c03783811916b255c974912b3fd2eceb30fa8146`이다. [TI 기준 커밋](https://github.com/TexasInstruments/ti-linux-kernel/commit/15b58b1dcd0e0a79d83740b81da1a1367f6f3f68) · [r47 기준 커밋](https://github.com/RobertCNelson/linux-stable-rcn-ee/commit/c03783811916b255c974912b3fd2eceb30fa8146)

## 패치 1. 예약 영역의 DMA heap 등록

- TI `drivers/dma-buf/heaps/carveout-heap.c`의 초기 예약 영역 등록, 페이지 정렬 검사, gen_pool, DMA-BUF exporter 및 캐시 동기화 경로를 이식 후보로 삼는다. `Kconfig` 및 `Makefile`에 `DMABUF_HEAPS_CARVEOUT`을 추가하고 대상 설정에서 활성화한다. 최초 후보는 TI와 동일하게 built-in으로 구성한다. `OF_RESERVED_MEM`, `HAS_IOMEM`, `GENERIC_ALLOCATOR` 의존을 보존한다. r47 헤더에도 reserved-memory 초기화 등록 매크로와 `fdt_node` 필드가 있으며, 초기 DT 접근 시점과 DMA API 호환성은 빌드 및 부팅에서 검증해야 한다. [TI heap 구현과 빌드 설정](https://github.com/TexasInstruments/ti-linux-kernel/tree/15b58b1dcd0e0a79d83740b81da1a1367f6f3f68/drivers/dma-buf/heaps)
- 현재 DT의 `dma-heap-carveout` 노드 이름으로 `carveout_vision_apps_shared-memories`가 등록되어야 한다. 해당 노드의 512 MiB 예약과 현재 캐시 속성을 유지한다. 첫 검증 기준은 sysfs 및 /dev에서 장치가 나타나고 4 KiB 할당·매핑·SYNC가 성공하는 것이다.

## 패치 2. SDK 주소 조회 ABI

- 변경 후보는 `include/uapi/linux/remoteproc_cdev.h`, `drivers/remoteproc/remoteproc_cdev.c`, `drivers/remoteproc/remoteproc_core.c` 및 관련 선언과 DMA-BUF 의존 설정이다. ioctl 분기 외에 파일별 참조 추적, DMA-BUF attach/map, 단일 연속 구간 검사, 종료 시 unmap/detach/put이 필요하다. TI 코드를 그대로 적용하면 shutdown-on-release 설정의 범위도 바뀌므로 그 동작은 r47 기준을 보존한다. [TI 문자 장치](https://github.com/TexasInstruments/ti-linux-kernel/blob/15b58b1dcd0e0a79d83740b81da1a1367f6f3f68/drivers/remoteproc/remoteproc_cdev.c) · [TI DMA-BUF 연결 구현](https://github.com/TexasInstruments/ti-linux-kernel/blob/15b58b1dcd0e0a79d83740b81da1a1367f6f3f68/drivers/remoteproc/remoteproc_core.c)
- SDK와 TI UAPI 모두 `_IOWR(0xB7, 0, ...)`과 32비트 fd + 64비트 주소 구조를 사용한다. AArch64에서는 주소 오프셋 8과 전체 크기 16을 빌드 시 대조한다. SDK 필드명 `phys`와 TI 필드명 `da`가 다르다. TI 구현의 실제 반환값은 remoteproc 장치에 매핑된 **`sg_dma_address()`**다. CPU 물리 주소와 같다고 가정하면 안 된다. SDK가 여는 `/dev/remoteproc0`은 현 보드에서 C66 DSP0이다. 해당 장치의 DMA 주소 매핑이 SDK 공유 영역 및 C71x가 사용하는 주소와 일치하는지 확인한다. [TI UAPI](https://github.com/TexasInstruments/ti-linux-kernel/blob/15b58b1dcd0e0a79d83740b81da1a1367f6f3f68/include/uapi/linux/remoteproc_cdev.h) · [SDK UAPI](../src/dma_buf_phys.h:33)
- TI 원본에서 attachment 리스트에 추가한 뒤 `copy_to_user`가 실패하면 fd close까지 참조가 남는다. 이식 시 실패 경로에서 즉시 해제하고, 동일 파일의 동시 요청과 코어 정리 중 리스트·참조 수명을 검토한다. 메모리 할당 실패 처리와 close 이후 매핑 해제도 빌드 리뷰에 포함한다. 장치 접근 권한은 현행 제한을 유지한다.

## 구현 및 검증 순서

1. r47 커밋의 별도 작업 트리에 위 두 패치를 독립 적용하고 실기 설정으로 관련 ARM64 커널 객체를 빌드한다. DMA-BUF namespace·의존성 및 사용자 ABI 크기를 확인한다.
2. 복구 가능한 시험 SD에서 exporter 검증을 먼저 완료한다. 두 패치를 포함한 부팅에서는 기존 `03 --allocate`로 SDK 장치 번호, 주소 범위 `[0xb8000000, 0xd8000000)` 및 캐시 동기화를 확인한다. 경로 식별에 실패하거나 주소가 다르면 04 진행을 보류한다.
3. 04에서 TIOVX 초기화와 피어 통신을 확인하고, 05에서 단일 모델 출력과 C71x/MMA 오프로딩을 검증한다.

이 문서는 최초 이식 범위 분석이다. 실제 주소 조회 패치에서는 remoteproc 코어 전체를 이식하는 대신 문자 장치 fd별 매핑을 구현했다. 두 패치의 실제 변경 범위와 빌드 기록은 [패치 안내](README-ko.md)를 참조한다.
