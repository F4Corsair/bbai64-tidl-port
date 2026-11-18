# 적용 전 미해결 항목

1. **커널 소스와 TI 확장.** 실기 소스 패키지 정보는 `linux-upstream 1trixie`이며 정확한 공급사 커밋은 미확인이다. [BeagleBoard 빌드·패치 저장소](https://github.com/beagleboard/arm64-mainline-linux)가 추적 출발점이다. 공개 태그 조회에서 정확한 트리를 확보하지 못했고 로컬 Git 조회는 DNS 오류로 실패했다. 아래 명령을 실행할 수 있는 호스트에서 소스 패키지 원본과 일치하는 패치·커밋을 확보한다.
   ```bash
   dpkg-query -W -f='${source:Package} ${source:Version}\n' linux-image-6.18.39-arm64-k3-r47
   apt-cache showsrc linux-upstream
   git ls-remote --tags https://github.com/beagleboard/arm64-mainline-linux.git '*6.18.39*'
   # 일치하는 공급사 deb-src가 구성된 별도 빌드 호스트에서
   apt-get source linux-upstream=1trixie
   ```
   소스 패키지 이름·버전만으로 트리 일치를 확정하지 않는다. 실제 패치 목록, 릴리스 문자열, 제공 설정과 커밋을 대조한다.
2. **heap과 ioctl.** 실기에는 `system/default_cma_region/reserved`만 관측됐다. `CONFIG_REMOTEPROC_CDEV=y`와 ioctl 함수 심볼은 TI 명령 처리의 증거가 아니다. 현재 커널과 SDK의 6.12.57-ti 소스에서 다음을 대조한다.
   ```bash
   git -C "$KERNEL_SOURCE" grep -nE 'dma-heap-carveout|RPROC_IOC_DMA_BUF_ATTACH|dma_buf_phys_data|rproc_device_ioctl'
   ```
   비교 범위는 `drivers/dma-buf/heaps/`의 DT carveout exporter/Kconfig, `drivers/remoteproc/remoteproc_cdev.c`의 dispatch, 대응 UAPI와 dma-buf pin/map 및 해제 경로다. SDK의 사용자 계약은 `app_utils/utils/mem/src/app_mem_linux_dma_heap.c`와 `app_utils/utils/mem/include/linux/dma_buf_phys.h`에 있다. 누락이 확인된 인터페이스만 이식하고 DMA 마스크·연속성·CPU 물리 주소와 장치 주소의 차이, 할당 수명·접근 제어를 검증한다. 표준 CMA heap만으로 이 계약은 성립하지 않는다. 적용 가능한 패치와 커널 빌드는 이번 산출물에 없다.
3. **DT/펌웨어.** 후보는 보드에서 부팅하지 않았다. GP/HS 및 서명 로더 계약, UART와 원본 SD 복구, TI SCI 자원과 MAIN R5F0_0의 ETHFW 의존성을 확인한다. R5F DA 0 TCM과 high heap은 정적 DDR 검사와 별도다. 커널 또는 펌웨어가 SDK 예약 범위를 다르게 해석하면 중단한다.
4. **검증 범위.** DMA probe는 호스트 할당·mmap·SYNC 및 TI 주소 반환을 검사한다. RPMsg 장치 열거는 DSP와의 왕복이나 캐시 일관성을 증명하지 않는다. 그 검증에는 호환 펌웨어의 전용 왕복 프로토콜 또는 실제 TIOVX 작업의 입력·출력 및 펌웨어 추적이 필요하다. 최종 MMA 증거는 SDK 펌웨어 실행 로그나 가속기 프로파일로 별도 확인한다.
5. **모델과 라이선스.** 테스트 모델의 컴파일 아티팩트는 아직 생성되지 않았다. 배치 가이드의 고정 태그 호스트 절차를 사용한다. SDK 바이너리와 헤더를 제삼자에게 공유하기 전에 SDK 매니페스트와 라이선스를 확인한다.

**현재 시험 범위:** 소스 접근이 없어도 현재 커널에서 후보 DT 및 코어 기동을 확인할 수 있다. 후보 DT가 적용된 뒤에도 heap이 노출되지 않거나 할당·주소 ioctl이 실패하면 SDK 런타임 단계는 보류한다. 이 판단은 소스 접근 여부가 아니라 실제 장치와 기능 검사 결과를 기준으로 한다. [검증 순서](deployment-guide-ko.md)
