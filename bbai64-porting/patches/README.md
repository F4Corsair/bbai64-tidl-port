# BeagleBoard r47용 Vision Apps 커널 패치

대상은 `6.18.39-arm64-k3-r47`, 커밋 `c03783811916b255c974912b3fd2eceb30fa8146`이다. 아래 두 패치를 순서대로 적용한다. [TI 기준 소스 및 이식 분석](ti-dma-backport-ko.md)

1. [0001 · Carveout heap](0001-dma-buf-add-TI-reserved-memory-carveout-heap.patch)은 TI SDK 커밋의 exporter를 이식한다. 할당 실패 정리와 반환 버퍼 초기화를 추가했다.
2. [0002 · Remoteproc 주소 조회](0002-remoteproc-support-scoped-TI-Vision-Apps-DMA-BUF-add.patch)는 SDK ioctl ABI를 지원한다. 특권 호출자의 Vision Apps heap 버퍼만 받고, 매핑이 연속이며 DMA 주소와 물리 주소가 같을 때만 주소를 반환한다. fd별로 매핑을 보관하고 닫을 때 해제한다. 기존 자동 종료 설정 동작을 보존한다.

r47 소스의 별도 작업 트리에서 실행한다. 셸 변수 `PATCH_DIR`는 이 디렉터리, `BOARD_CONFIG`는 실기에서 수집한 kernel.config의 절대 경로로 지정한다.

```bash
git apply --check "$PATCH_DIR"/0001-*.patch
git apply "$PATCH_DIR"/0001-*.patch
git apply --check "$PATCH_DIR"/0002-*.patch
git apply "$PATCH_DIR"/0002-*.patch

export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
mkdir -p out
scripts/kconfig/merge_config.sh -m -O out "$BOARD_CONFIG" "$PATCH_DIR/vision-apps-r47.config"
make O=out olddefconfig
make O=out -j"$(nproc)" drivers/dma-buf/heaps/carveout-heap.o drivers/remoteproc/remoteproc_cdev.o
```

깨끗한 소스에서의 순차 적용, ARM64 객체 컴파일, ioctl 번호·구조체 크기·필드 오프셋 일치를 확인했다. [검증 기록](arm64-build-validation.log)

다음 단계는 별도 시험 커널 릴리스로 시험 SD에서 부팅하는 것이다. 현재 시스템의 모듈과 일치시키기 위해 이미지와 모듈을 한 세트로 관리한다. 기존 부팅 경로를 확보한 뒤 heap 등록, `03 --allocate`, TIOVX 초기화 순으로 검증한다. 주소 조회에서 `ERANGE`가 나오면 DSP0의 DMA 주소 매핑과 공유 영역을 먼저 대조한다. 보드 부팅과 DMA 동작은 실기에서 확인해야 한다.

`6.18.39-arm64-k3-r47-tidl1` 전체 이미지·모듈 빌드와 배포 묶음 검증까지 완료했다. [보드 적용 가이드](../docs/r47-kernel-deployment-ko.md)에서 설치와 복구 절차를 확인할 수 있다.

Step 03의 DMA 매핑 실패를 수정하는 0003 패치를 추가했다. [tidl2 빌드 시작점](tidl2-build-start-ko.md)에 순차 적용 검증과 빌드 명령을 기록했다.

## 0004: RPMsg 실제 local endpoint 노출 (tidl3 후보)

자동 할당 후 sysfs src가 요청값 -1로 남는 문제를 보완한다. src_show가 ept_lock으로 보호하면서 실제 열린 endpoint 주소를 반환한다. 0001–0003을 유지한 로컬 작업 소스에 적용했고 out-tidl3 설정을 준비했다. **커널 빌드는 수행하지 않았다.** [사용자 빌드 가이드](tidl3-build-start-ko.md). 이 패치는 noeth 펌웨어를 유지하며 전체 OS 재생성이 필요하지 않다.
