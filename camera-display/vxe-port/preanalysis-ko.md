# BBAI64 VXE384MP2 H.264 인코더 포팅 사전 조사

[English](preanalysis-en.md) · [D435i 연결 검증](../d435i-rgb/preflight-ko.md)

## 결론

**r47용 외부 인코더 모듈과 BBAI64 DT에 VXE 노드 한 개를 추가하는 구성이 첫 포팅 후보**다. 현재 Debian 13.6과 `6.18.39-arm64-k3-r47-tidl3`를 유지한다. 의존 API 때문에 외부 모듈 포팅이 불가능하다고 확인된 경우에만 필요한 커널 변경을 산정한다. 이번 조사는 정적 확인으로 마쳤으며 빌드, 보드 적용 및 스트리밍은 후속 작업이다.

사용자 시험에서 D435i 1080p30 YUYV, 소프트웨어 축소·JPEG 30 fps, TCP/SSH ProxyJump 전송이 동작했다. 원격 수신에는 심한 끊김이 있었고 테스트한 D435i 모드에서 MJPEG 직접 출력은 사용할 수 없었다. H.264 하드웨어 인코딩의 CPU·전송량 개선 폭은 후속 비교에서 측정한다.

## 확인한 구성과 포팅 범위

- **드라이버 — 포팅 필요.** PSDK Linux 11.02.00.04의 로컬 `tisdk-adas-image-j721e-evm.tar.xz`에는 `updates/vxe-enc.ko`와 `vxd-dec.ko`가 들어 있다. opkg의 `ti-vxe-vxd-driver`는 `6.12-r0.845`, 레시피는 `ti-vxe-vxd-driver_6.12.bb`다. 제품 패키지가 두 모듈과 `ti-multimedia-udev`를 함께 요구하는 것은 패키지 구성이다. 인코더 모듈의 `.modinfo`는 디코더 의존성을 선언하지 않는다. TI 모듈은 TI 6.12.57용이며 r47의 ABI로 빌드해야 한다. r47 트리 및 설정에서 전용 VXE 옵션과 드라이버는 발견되지 않았다. TI의 외부 모듈 레시피 이력은 확인했으나 이 이미지의 **정확한 소스 SRCREV와 패치 목록은 미확인**이다. 다음 단계에서 릴리스 매니페스트가 가리키는 Yocto 레이어와 적용된 bbappend를 확보해 `SRC_URI`, `SRCREV`, 패치를 확정한다. [TI 릴리스 노트](https://software-dl.ti.com/jacinto7/esd/processor-sdk-linux-jacinto7/11_02_00_04/exports/docs/devices/J7_Family/linux/Release_Specific_Release_Notes.html) · [TI 레시피 이력](https://git.enea.com/cgit/linux/meta-ti.git/log/?h=scarthgap-next&id=a49d78970f36ad28d3c18b77288d870864e44797&showmsg=1)
- **r47 의존성 — 일부 확인.** TI 모듈은 `v4l2-mem2mem,videobuf2-v4l2,videodev,videobuf2-dma-sg,videobuf2-common`에 의존한다. 특히 SG 경로가 근거이며 DMA-contig로 대체한다고 가정하지 않는다. 로컬 tidl3 설정에는 V4L2 mem2mem, VB2 V4L2와 DMA-SG가 모듈로 있고 DMA CMA가 켜져 있다. TI 모듈의 미정의 심볼 119개를 기존 r47 `Module.symvers`와 비교해 115개가 일치함을 확인했다. 미일치 심볼은 `__mutex_init`, `init_timer_key`, `mutex_is_locked`, `sg_next`다. 대상 헤더에서 인라인되거나 다른 심볼로 바뀔 수 있으므로 소스 수준에서 확인한다. 소스 확보 후 플랫폼 콜백, V4L2/vb2 큐·DMA 헬퍼, 런타임 PM API와 Kbuild의 6.12→6.18 호환을 확인하고 동일 r47 설정·심볼·툴체인으로 외부 모듈 modpost를 통과시킨다. 기존 커널 변경이 필요하면 새 릴리스 이름으로 분리한다.
- **Device Tree — 변경 필요.** SDK 이미지의 SK와 common-proc-board DTB 모두 `video-encoder@4200000`, `img,vxe384`, MMIO 크기 `0x100000`, GIC SPI 181 level-high, 전원 도메인 153 exclusive를 정의한다. 두 노드 모두 자체 `clocks`나 `memory-region` 속성이 없다. 로컬 BBAI64 TIDL 후보 DTB에는 인코더 노드가 없고 `k3_pds`는 존재한다. 후보는 해당 노드를 main bus에 추가하고 BBAI64 쪽 전원 컨트롤러 참조를 사용한다. SDK DTB의 숫자 phandle을 그대로 복사하지 않는다. 병합 후 기존 reserved-memory, remoteproc, RPMsg 및 DMA heap 속성이 동일한지 검사한다. 장치 DMA 마스크와 SG/MMU 주소 제약은 드라이버 소스로 추가 확인한다.
- **펌웨어 — 인코더와 디코더를 구분.** VXE 모듈에는 `topaz_upload_firmware`가 있고 `.modinfo`에 외부 펌웨어 선언은 없다. `vxd-dec-fw` 패키지의 `pvdec_full_bin.fw`는 디코더용이다. 펌웨어 요청 API를 직접 참조하는 미정의 심볼도 없어 내장 페이로드 가능성이 높다. 인코더 펌웨어의 출처와 재배포 조건은 소스 확인 전 미확인이다. 모듈과 패키지에서 MCU2_0/C71x 펌웨어 교체를 요구한다는 근거는 찾지 못했다. 기존 noeth 및 DSP 펌웨어를 유지한다.
- **GStreamer — 등록 조건 확인 필요.** V4L2 장치에서 mem2mem, NV12 입력(OUTPUT), H.264 출력(CAPTURE)과 실행 계정 권한을 먼저 확인한다. 이후 `gst-inspect-1.0 v4l2h264enc`로 등록을 확인한다. 노드가 정상이고도 미등록이면 Debian 플러그인의 장치 탐색·caps 및 TI GStreamer 패치 차이를 대조한다. 초기 검증에는 복사 기반 NV12 변환을 사용한다. 1080p에서 stride·버퍼 정렬·협상된 크기 및 crop을 확인한 후 DMA-BUF·하드웨어 스케일링을 검토한다. [TI NV12/H.264 및 GStreamer 예제](https://software-dl.ti.com/jacinto7/esd/processor-sdk-linux-jacinto7/11_02_00_04/exports/docs/linux/Foundational_Components_Multimedia_D5520_VXE384.html)

## 후속 검증과 복구

1. **배포 전.** 사용자가 빌드할 r47 후보의 모듈·DTB·설정 SHA256과 원본 소스 리비전을 보존한다. 모듈 vermagic, 심볼 및 DT diff를 확인한다. 기존 tidl3 부트 항목과 펌웨어 링크를 보존한 채 새 부트 항목에만 후보를 적용한다.
2. **인코더 단독.** `v4l2-ctl --list-devices`와 인코더 노드별 `--all`, `--list-formats-out`, `--list-formats`로 양쪽 큐와 제어를 확인한다. `videotestsrc → video/x-raw,format=NV12,width=1280,height=720,framerate=30/1 → v4l2h264enc → h264parse → filesink`에서 300프레임을 기록한다. 산출물을 호스트에서 디코딩해 300프레임과 720p 해상도를 확인한다. 커널 로그에 인코더 timeout·DMA 오류가 없고 기존 TIDL 모델 반복 시험이 통과해야 한다.
3. **카메라와 네트워크.** D435i의 YUYV를 소프트웨어로 NV12 변환·축소해 로컬 인코딩을 먼저 검증한다. 이전 로그의 짧은 오류 버퍼와 같은 V4L2 입력 오류를 집계하고 폐기한다. 그다음 같은 TCP/SSH ProxyJump 구간에서 JPEG와 H.264를 동일 출력 해상도·FPS로 비교한다. 송신 CPU, 전송 바이트, 수신 FPS·프레임 누락을 기록한다. 동일 소스의 로컬 인코딩과 원격 수신 수치를 따로 보존한다.
4. **중단·복구.** probe 실패, 인코더 timeout, DMA 오류, TIDL 회귀 또는 기존 DT 메모리 변경이 나오면 다음 단계로 넘어가지 않는다. 기존 tidl3 항목으로 부팅해 기존 D435i RGB 및 TIDL 검증을 다시 실행한다. 보드 적용과 커널 빌드는 사용자가 수행한다.
