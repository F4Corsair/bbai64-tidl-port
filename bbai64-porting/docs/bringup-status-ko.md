# BBAI64 TIDL 포팅 현황과 공유 메모리 선택지

## 최신 상태 보충 — Step 05 IPC 초기화 장애

아래 이전 DMA 조사 기록보다 이 절의 현황을 우선한다.

- **확인됨:** 사용자 적용 커널에서 Vision Apps heap이 나타났고 Step 03의 호스트 할당·주소 조회를 통과했다. 모델의 49개 노드가 TIDL로 분할됐으나 원격 노드 생성은 IPC 오류로 실패했다. DSP 왕복 추론은 아직 성공하지 않았다.
- **확인됨:** 기존 Step 04는 SDK 초기화 함수가 IPC 오류 상태를 뒤에서 덮어써 성공으로 표시할 수 있었다. 스크립트를 수정해 IPC 및 원격 서비스 오류 로그도 실패로 판정한다. 이전 성공은 전체 IPC 정상의 근거로 사용할 수 없다.
- **확인됨:** TI RPMsg 0.6.11 공식 커밋 `b1e4d172f39081db81305fa50ccaafd3ef8ae3a6`에는 upstream 커널의 local endpoint `src` 속성 부재 대응이 있다. 해당 소스로 AArch64 라이브러리를 빌드했고 SDK 0.6.10과 공개 심볼 및 SONAME이 일치한다. 별도 경로로 시험하도록 준비했다. [시험 파일과 절차](../rpmsg-work/README-ko.md)
- **미확인:** endpoint=0 대체 처리의 TIOVX 실제 왕복 호환성. 새 라이브러리는 아직 보드에서 실행하지 않았다.
- **확인됨:** 읽기 전용 조사에서 MAIN R5F0_0은 running이지만 port 13의 rpmsg_chrdev 서비스가 보이지 않았다. **가능성 높음인 원인 후보:** IPC보다 먼저 실행되는 ETHFW 초기화에서 대기. 원인 확정에는 해당 코어 trace가 필요하다.

다음 순서는 사용자가 MAIN R5F0_0 trace를 수집하고, 새 라이브러리를 프로세스별로 지정하여 수정된 Step 04를 수행하는 것이다. 실패하면 전체 로그를 분석하고 Step 05 반복을 멈춘다. 성공한 경우에만 같은 라이브러리 경로로 Step 05를 실행해 원격 노드 생성과 추론 반환을 검증한다. 현재 DT·커널·펌웨어를 추가 변경할 근거는 없다. 원격 설치나 상태 변경은 수행하지 않았다.

## 현재 상태

**후보 DT와 Vision Apps 코어 기동 검사를 통과했다. 현재 막힌 지점은 Linux에서 Vision Apps 공유 버퍼를 할당할 DMA heap이다.**

| 사용자 측 결과 | 확인 범위 |
|---|---|
| 01 성공 | 부팅 중인 DT의 후보 예약 메모리 속성과 코어 phandle이 검사 기준에 일치했다. 인자 없이 실행했으므로 extlinux 항목 이름 확인은 범위 밖이다. 현재 포팅 판단에는 적용된 DT가 직접 근거다. |
| 02 성공 | SDK Vision Apps 대상 5개(C71x, C66x 2개, MAIN R5F 2개)가 running이고 기존 MCU R5F는 attached였다. 현재 펌웨어 파일은 스크립트가 검사한 SDK 파일과 일치했다. 02의 결과만으로 RTOS 피어 동기화 완료와 C71x 서비스 응답까지 판단할 수는 없다. |
| 03 일반 사용자 및 sudo 모두 실패 | `/dev/dma_heap/carveout_vision_apps_shared-memories`가 문자 장치로 확인되지 않았다. 03은 이 검사에서 즉시 종료하므로 두 실행 모두 C71x RPMsg 검사, 버퍼 할당, 주소 조회 ioctl에 도달하지 않았다. 권한을 높여도 현재 장치 노출 결과는 같았다. |

근거는 사용자가 전달한 01–03 요약과 [01](../scripts/check-live-dt.py), [02](../scripts/02-check-remoteproc.sh), [03](../scripts/03-check-ipc-dma.sh)의 통과 조건이다. 전체 로그는 이 보고서 작성 시 제공된 요약과 구분한다.

## 여기까지 포팅에 필요했던 작업

1. **BBAI64 DT에 SDK 메모리 맵 통합.** 필요한 코어의 DMA 풀과 펌웨어 영역, IPC와 공유 메모리 영역을 SDK 배치에 맞췄다. 예를 들어 C71x 펌웨어 영역은 기본 DT의 `0xa8100000`에서 SDK ELF가 사용하는 `0xb2100000`으로 바뀌었다. 실제 적용은 01로 확인했다. [포팅 계획](porting-plan-ko.md)
2. **대응 펌웨어 세트 배치.** C71x의 TIDL 타깃과 SDK 초기화 구성에 참여하는 C66x·MAIN R5F를 같은 버전의 세트로 올렸다. 02로 코어 기동과 파일 일치를 확인했다. [펌웨어 매핑](../staging/manifests/firmware-map.tsv)
3. **남은 필수 작업은 공유 버퍼 경로 확보다.** 후보 DT에 `dma-heap-carveout` 영역 `[0xb8000000, 0xd8000000)`이 있어도, 커널이 해당 영역을 allocator로 등록해야 SDK가 장치를 열 수 있다. SDK allocator는 그 장치에서 DMA-BUF를 할당하고, 별도로 `/dev/remoteproc0`의 `RPROC_IOC_DMA_BUF_ATTACH`를 사용해 버퍼 주소를 얻는다. heap과 주소 조회 중 하나라도 이용할 수 없으면 현재 SDK 라이브러리의 공유 버퍼 경로에서 추론을 진행할 수 없다. [SDK 메모리 맵](../staging/dt/sdk-memory-map.dtsi:119) · [SDK allocator](../../sdk_original/app_utils/utils/mem/src/app_mem_linux_dma_heap.c:85) · [주소 조회 호출](../../sdk_original/app_utils/utils/mem/src/app_mem_linux_dma_heap.c:705)

## 이후 탐색 순서와 선택지

**1. 읽기 전용 재조사 결과.** 실행 커널 `6.18.39-arm64-k3-r47`의 live DT에 `dma-heap-carveout` 노드가 있고, 커널 로그는 `[0xb8000000, 0xd8000000)` 512 MiB 예약을 확인한다. `/sys/class/dma_heap`과 `/dev/dma_heap` 양쪽에 `default_cma_region`, `reserved`, `system`만 표시된다. 현재 병목은 Vision Apps heap의 커널 등록이다. 수집한 로그에서 해당 exporter의 구체적인 등록 오류는 확인되지 않았다. [실기 원본 로그](../../docs/bbai64-survey/dma-followup.log)

- **exporter 구현 미확인.** 모듈 파일, `modules.builtin`, 커널 설정 및 System.map의 관련 이름에서 지원 근거가 나오지 않았다. 조사한 설치 파일은 헤더 트리이고 실행 커널 소스 링크는 없다. 빌드에서 exporter가 빠졌을 가능성이 높지만, 코드 누락과 초기화 경로의 문제를 확정하려면 정확한 소스·패치 구성이 필요하다.
- **주소 조회 ioctl 미검증.** `rproc_device_ioctl` 심볼은 보이지만, 헤더 트리에서 해당 명령을 처리하는 소스는 확보하지 못했다.
- **C71x RPMsg 등록 확인.** `64800000.dsp/remoteproc2` 아래 `virtio3.rpmsg_chrdev.-1.13`과 제어 장치가 보인다. MAIN R5F0_0(`remoteproc5`)에서는 제어 및 이름 서비스 항목만 관측됐다. TIDL 초기화가 나중에 피어 endpoint에서 실패하면 이 코어의 서비스 광고를 먼저 확인한다.

| 선택지 | 조건과 작업 | 판단 |
|---|---|---|
| **A. 현재 커널에 있는 exporter 활용** | 구현이 있으면 DT 바인딩, 빌드 설정, 모듈 또는 등록 로그를 대조해 원인을 고친다. 장치가 나타나면 동일한 커널에서 SDK 방식의 주소 조회까지 확인한다. | 가장 먼저 조사할 경로. 기존 구현으로 해결되면 변경이 작다. |
| **B. 누락된 TI 기능만 이식** | 실제 구현 누락이 확인되고 커널 작업을 할 수 있을 때, 현재 커널 계열에 exporter와 실제로 빠진 주소 조회 경로를 보완한다. | SDK 바이너리와 펌웨어를 유지할 수 있다. 정확한 소스와 빌드·복구 경로가 필요하므로, TI Git에 접근할 수 없는 현재는 구체적 소스 확보 가능성이 확인될 때까지 보류한다. [TI exporter 소스 참고](https://git.ti.com/cgit/ti-linux-kernel/ti-linux-kernel-next/tree/drivers/dma-buf/heaps/carveout-heap.c?id=0545e6ef5f73ccd870bf2c0aa41ea3567f073f35) |
| **C. 기존 커널에서 사용자 공간 allocator 수정** | 현재 커널에서 SDK 허용 주소 범위를 충족하는 연속 버퍼를 제공할 수 있는지, DSP가 사용할 주소를 얻는 지원 경로가 있는지 먼저 확인한다. 두 조건이 성립할 때만 allocator 수정·재빌드를 검토한다. 캐시 동기화와 버퍼 수명도 유지해야 한다. | 커널 교체를 피할 수 있으나 수정 범위가 크다. 기본 CMA나 system heap에 SDK 이름의 링크를 추가하는 것만으로는 주소 범위와 주소 조회가 해결되지 않는다. [Linux DMA heap](https://docs.kernel.org/6.17/userspace-api/dma-buf-heaps.html) · [DMA-BUF 공유와 동기화](https://docs.kernel.org/driver-api/dma-buf.html) |

**2. 공유 버퍼를 확보한 뒤 필요한 검증만 한다.** SDK heap에서 실제로 할당된 버퍼의 주소가 기대 범위에 들어오는지 확인하고, 주소 조회 호출이 실패하면 그때 errno를 기준으로 권한·장치 매핑·UAPI 구현을 좁힌다. 이후 SDK 라이브러리 초기화와 단일 ONNX 모델로 결과와 C71x/MMA 실행을 확인한다. 현재 단계에서는 같은 03을 sudo로 반복하거나, 통과한 01·02를 다시 실행할 필요가 없다. DT나 펌웨어를 바꾸는 선택지를 실제로 적용한다면 영향을 받은 단계만 다시 확인한다.

다음 작업은 **실행 커널과 일치하는 BeagleBoard 소스·패치 구성에서 exporter와 ioctl 분기를 확인하는 것**이다. 현재 증거로는 DT 주소나 장치 노출 설정을 수정할 근거가 없다. 정확한 빌드 근거를 확보하기 전에는 최소 이식 범위를 확정할 수 없다. A가 불가능하고 C의 주소 계약도 충족할 수 없다면, 현재 커널과 SDK 바이너리를 유지하는 조건으로는 포팅을 여기서 보류할 근거가 된다.

### r47 소스 대조로 확정한 후속 판단

공개 `6.18.39-arm64-k3-r47` 태그의 커밋 `c03783811916b255c974912b3fd2eceb30fa8146`에서 **TI carveout exporter와 `RPROC_IOC_DMA_BUF_ATTACH` 처리 분기가 모두 빠져 있음**을 확인했다. 앞 절의 구현 미확인 판정을 대체한다. DT의 512 MiB 예약은 이미 성공했으므로, SDK 바이너리 재사용 경로에는 두 커널 기능을 함께 보완해야 한다. [소스 및 판정 근거](../../docs/bbai64-porting-strategy-ko.md#section-14)

SDK 릴리스 문자열과 일치하는 TI 커밋에서 두 구현을 찾았다. r47의 이식 범위와 검증 조건을 [TI DMA 기능 이식 범위](../patches/ti-dma-backport-ko.md)에 정리했다. 특히 주소 조회의 반환값은 DMA 주소이므로 SDK가 기대하는 공유 주소와의 일치 여부를 실기에서 확인해야 한다.

r47용 exporter와 주소 조회 패치를 작성했고 ARM64 객체 빌드와 SDK의 ioctl ABI 일치를 확인했다. 다음 검증은 전체 이미지·모듈 빌드 및 시험 SD에서의 heap·DMA 주소 확인이다. [패치 및 재현 절차](../patches/README-ko.md)

전체 ARM64 이미지와 모듈을 빌드하고 `6.18.39-arm64-k3-r47-tidl1` 로컬 배포 세트를 만들었다. 재부팅 후 heap 노출 및 DMA 주소를 확인하는 명령과 SD 오프라인 복구 절차는 [보드 적용 가이드](r47-kernel-deployment-ko.md)에 있다.
