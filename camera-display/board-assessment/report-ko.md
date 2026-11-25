# BBAI64 카메라·디스플레이 지원 사전 조사

2026-11-25 · [English](report-en.md) · [실기 조회 기록](board-inventory.txt) · [작업 과정](../worklog-ko.md) · [성과](../outcomes-ko.md)

## 1. 결론과 기준 환경

D435i RGB는 현재 커널에서 가장 먼저 검증할 수 있다. Mini DisplayPort는 Linux에서 커넥터를 등록했으며, 실제 출력 검증 전에 MCU2_0의 DSS 초기화와 MHDP 펌웨어 상태를 확인해야 한다. IMX219는 BBAI64용 카메라 오버레이와 CSI 소유권 정리가 선행된다. VPAC 하드웨어 ISP는 기존 SDK의 C API로 접근할 후보가 있으며, Edge AI 미들웨어 도입은 후순위다.

읽기 전용 SSH에서 Debian 13.6, `6.18.39-arm64-k3-r47-tidl3`, 부트 표식 `tidl-kernel-test-3`를 확인했다. 기존 Python ONNX Runtime 1.15.0/TIDL EP 추론은 [포팅 검증 기록](../../bbai64-porting/python-ort-validation/results-ko.md)을 기준으로 한다. SDK는 J721E RTOS 11.02.00.06, Linux 11.02.00.04, TIDL Tools 11_02_04_00 조합이다. 이번에는 하드웨어 연결, 스트리밍, 그래프 실행 또는 빌드를 수행하지 않았다. [TI 버전 호환표](https://github.com/TexasInstruments/edgeai-tidl-tools/blob/master/docs/sdk_version_compatibility_table.md)

| 기능 | 판단 | 근거 및 후속 조건 |
|---|---|---|
| USB UVC·V4L2 및 Media Controller·Subdevice | **Available** | 실기 `USB_VIDEO_CLASS=m`, `MEDIA_CONTROLLER=y`, `VIDEO_V4L2_SUBDEV_API=y`, `uvcvideo.ko.xz`. USB 5 Gbit/s 루트 허브 확인. |
| D435i RGB | **Available** (캡처 경로), 무오류 기준 미충족 | 실기에서 1080p30 YUYV로 정상 크기 300프레임과 오류 버퍼 1개를 확인했다. [연결 시험 결과](../d435i-rgb/preflight-ko.md) |
| D435i Depth·IMU | **Porting Required** | 검색 경로에서 librealsense 미확인. Debian arm64 사용자 공간과 USB 권한 확인이 먼저이며, 현재 커널에 대한 패치 필요성은 미확정. |
| IMX219 RAW | **Configuration Required**, **Porting Required** | 수신기·센서 모듈은 설치됨. live DT의 CSI shim 두 개 및 RX D-PHY 두 개는 비활성 상태이며 센서 노드는 발견되지 않았다. 보드용 오버레이 검증·이식과 RTOS 소유권 조정 필요. |
| MiniDP | **Available** (드라이버 등록), **Hardware Validation Required** (출력) | TIDSS 및 MHDP가 바인딩됐고 `card0-DP-1`은 `disconnected`. 현재 펌웨어에서 DSS 소유권 조정 필요. |
| VPAC VISS·MSC·LDC, DSP 색 변환 | **Hardware Validation Required** | SDK 및 ELF·호스트 심볼 근거가 있다. 현재 Debian에서 그래프 생성과 프레임 처리는 미검증. |
| DMA-BUF 공유 | **Configuration Required**, **Hardware Validation Required** | 실기에 CMA·Vision Apps carveout heap이 있고 장치 권한은 root 전용이다. 추론 서비스 실행 계정의 접근과 장치 간 import는 별도 검증. |

## 2. Linux 캡처 및 출력

- **CSI.** 실행 커널 설정 및 설치 모듈에서 `VIDEO_TI_J721E_CSI2RX=m`, `VIDEO_CADENCE_CSI2RX=m`, `PHY_CADENCE_DPHY_RX=m`, `VIDEO_IMX219=m`을 확인했다. live DT의 shim은 `4500000/4510000`, RX D-PHY는 `4580000/4590000`이며 네 노드 모두 disabled다. 로컬 후보 DTB에도 같은 구성이 있고, shim 아래 Cadence bridge가 D-PHY를 참조한다. 센서부터 CSI 캡처까지의 커널 패치 필요성은 현재 근거로 확인되지 않았다. 근거는 `bbai64-porting/kernel-work/linux/drivers/media/platform/ti/j721e-csi2rx/`와 `arch/arm64/boot/dts/ti/k3-j721e-beagleboneai64.dts`다.
- **오버레이.** 실기 `/boot/firmware/overlays`와 로컬 r47 트리에서는 J721E SK용 `k3-j721e-sk-csi2-dual-imx219`가 확인됐다. 이 소스는 SK의 `csi_mux`, `cam0_i2c`, `cam1_i2c`에 의존한다. BeagleBoard 공식 5.10 브랜치의 BBAI64 CSI1 소스는 `main_i2c1`, 주소 `0x10`, 24 MHz, GPIO0_107, 2레인을 사용한다. 최신 r47용 완성 오버레이와 CSI0 원본은 이번에 검증하지 못했다. CSI1을 첫 후보로 삼고, r47의 `sony,imx219.yaml` 및 드라이버에 따라 실제 전원과 reset, pinctrl, 양방향 endpoint와 D-PHY를 검증한다. 카메라 전용 오버레이의 범위는 해당 센서와 연결 경로다. 후속 작업에서 후보 DTB에 오프라인으로 합성해 적용 전후 reserved-memory, remoteproc `memory-region`, DMA heap, 기존 활성 주변장치가 같은지 검사한다. 15핀 모듈의 경우 BBAI64 22핀 소켓과 맞는 케이블·핀 배열을 확인한다. [BeagleBoard CSI1 소스](https://github.com/beagleboard/BeagleBoard-DeviceTrees/blob/v5.10.x-ti-unified/src/arm64/overlays/BBAI64-CSI1-imx219.dts) · [카메라 연결 문서](https://docs.beagleboard.org/accessories/cameras.html)
- **MiniDP.** `4a00000.dss → a000000.dp-bridge → DP-1`에서 각각 `tidss`와 `cdns-mhdp8546` 바인딩을 확인했다. 부트 로그의 SAPB 오류는 드라이버 메시지상 HDCP 미지원이다. `cdns-mhdp8546-core.h`의 `FW_NAME`은 `cadence/mhdp8546.bin`이며, 조회한 펌웨어 디렉터리에서 파일을 발견하지 못했다. 로컬 tidl3 빌드의 `CONFIG_EXTRA_FIRMWARE`에 이 파일이 포함되어 있어 내장 펌웨어가 로딩 경로로 유력하다. 실제 실행 이미지의 설정과 firmware 요청 결과는 별도로 확인한다. 기본 테스트 패턴과 KMS scanout은 CPU 버퍼와 DRM/KMS로 시작한다. GPU 가속 합성·EGL 또는 기존 Vision Apps 라이브러리를 사용할 때는 별도의 EGL/GLES/GBM 의존성을 확인한다. [Linux DRM/KMS](https://docs.kernel.org/gpu/drm-kms.html)
- **D435i.** RGB는 `v4l2-ctl`로 실제 컬러 인터페이스를 찾아 일반 UVC로 확인한다. Depth는 포맷·메타데이터·타임스탬프를, IMU는 가속도·자이로와 영상 동기화를 따로 검사한다. librealsense native는 V4L2/UVC 및 HID/IIO의 동작에 의존한다. RSUSB는 libusb 및 장치 권한을 사용하는 대안이다. 카메라 펌웨어와 SDK 버전의 조합을 고정한 뒤 두 경로를 비교하고, 요구하는 스트림이 실패한 경우에만 해당 드라이버의 패치 범위를 산정한다. 공급자 DKMS의 지원 범위를 r47에 그대로 적용할 근거는 없다. [D435i IMU](https://github.com/realsenseai/librealsense/blob/master/doc/d435i.md) · [Linux 백엔드 비교](https://github.com/realsenseai/librealsense/blob/master/doc/installation_jetson.md)

## 3. Firmware 소유권과 TIOVX

실기 `5c00000.r5f`가 running이고 `j7-main-r5f0_0-fw` 파일 해시 `567e257b39a2a6082c8a2394a3e49dea33b5add790449accae6d225f6bb5d695`는 [noeth 배포 산출물](../../bbai64-porting/firmware-work/deployment-noeth-ko.md)과 일치한다. 이 값은 부트 후 조회한 파일의 해시다. MCU2_1, 두 C66x와 C71x도 running이다.

| 자원 | 소스 및 링크 근거 | 후속 소유권 |
|---|---|---|
| CSI2RX·Capture | `BUILD_MCU_BOARD_DEPENDENCIES=yes` → `ENABLE_CSI2RX` → `appCsi2RxInit`, `tivxRegisterVideoIOTargetCaptureKernels` | Linux V4L2·I²C |
| DSS | 같은 플래그 → `ENABLE_DSS_SINGLE`·`ENABLE_DSS_EDP` → `appDssDefaultInit`, Display 및 Display M2M Target 등록 | Linux TIDSS/MHDP |
| VPAC | 독립 `ENABLE_VHWA_VPAC` → `appVhwaVpacInit`, MCU2_0 VISS/MSC/LDC/NF/FC 등록 및 AEWB Target 등록 | MCU2_0 |
| DMPAC·DSP | J721E `app_init.c`의 DMPAC SDE/DOF 경로, C66x OpenVX 및 ImgProc, C71x TIDL/TVM/ImgProc 등록 분기 | MCU2_1 및 각 DSP |

근거는 SDK의 `vision_apps/platform/j721e/rtos/common/{app_cfg_mcu2_0.h,app_init.c}`, 로컬 noeth ELF·map 및 `firmware-work/build.sh`다. `BUILD_ENABLE_ETHFW=no`와 보드 주변장치 설정은 독립이다. Linux DP 바인딩은 RTOS의 DSS 경로가 비활성임을 입증하지 않는다. 후속 MCU2_0 후보는 `BUILD_MCU_BOARD_DEPENDENCIES=no`로 CSI2RX/TX·DSS·보드·I²C 초기화를 해제하고 FVID2·VPAC·IPC를 유지하는지 비교한다. 소스에서 확인한 초기화 경로와 실기에서 특정 시점의 레지스터 소유권은 구분한다. 독립 후보의 ELF/map, resource table, SHA256, 기존 주소 범위와 추론 회귀 검증을 통과한 뒤 사용자가 적용한다.

`libtivision_apps.so.11.2.0`은 실기 사용자 staging에서 확인했다. 로컬 대응 ELF는 `tivxHwaLoadKernels`, `tivxVpacVissNode`, `tivxVpacMscScaleNode`, `tivxVpacLdcNode`, `tivxAewbNode`, `vxColorConvertNode`, `tivxCreateRawImage`, `tivxReferenceImportHandle/ExportHandle`, `tivxMemTranslateFd/VirtAddr`를 export한다. 현재 스테이징 헤더는 ONNX Runtime 중심이므로 C 그래프에는 동일 SDK의 TIOVX, Imaging 및 필요한 Vision Apps 헤더를 사용한다. ELF의 NEEDED에는 EGL, GLESv2, GBM, `libti_rpmsg_char.so.0`와 시스템 라이브러리가 있다. 심볼만으로 전체 Vision Apps 기능, 실행 ABI 또는 호스트-Target 등록 일치를 판정할 수 없다.

VISS의 Bayer→YUV 경로는 MCU2_0 VPAC, OpenVX 색 변환은 SDK `tiovx/kernels/openvx-core/c66x/vx_color_convert_target.c`에 DSP Target 구현이 있다. RGB가 필요하면 VISS NV12 이후 지원되는 DSP 포맷 조합 또는 CPU 변환을 검증한다. LDC는 렌즈별 보정/mesh가 별도로 필요하다. DMA-BUF는 CSI 드라이버 `VB2_MMAP | VB2_DMABUF`와 TIOVX 메모리 API를 출발점으로 삼는다. 복사 경로를 먼저 검증하고, zero-copy는 plane별 크기·offset·pitch, 정렬, 물리 주소 제약, 캐시 동기화, FD·버퍼 수명과 heap 권한이 모두 맞을 때 전환한다.

## 4. IMX219 ISP와 DCC 최소 구성

- SDK 이미지 `tisdk-adas-image-j721e-evm.tar.xz`의 `/opt/imaging/imx219/linear/`에 `dcc_viss*.bin` 및 `dcc_2a*.bin`이 있다. 두 계열 모두 기본 파일, `_10b` 파일 및 320×240, 640×480, 1280×720, 1640×1232, 1920×1080 해상도별 파일이 있다. SDK 소스의 `imaging/sensor_drv/include/dcc_{viss,2a}_imx219.h`와 `imaging/tools/default_DCC_profile_gen/configs/imx219_properties.txt`가 추가 근거다. 헤더 배열과 이미지의 개별 파일이 동일하다는 판단에는 별도 비교가 필요하다.
- 센서 mode와 media-bus code, 캡처 fourcc, Bayer 순서(플립 포함), RAW8/RAW10, RAW10 packed 또는 16비트 컨테이너, stride, 실제 출력 크기를 먼저 읽는다. SDK 예제의 1920×1080은 참고 모드다. 실제 모드와 일치하는 VISS/2A 쌍을 사용하고, NoIR 프로파일은 미확인으로 둔다. 기본 IMX219 DCC는 초기 시험 후보이며, IR 유입이 있는 환경에서 색·AWB·노출을 비교하고 필요하면 별도 튜닝한다.
- Linux V4L2 RAW를 `tivxCreateRawImage` 입력으로 준비하고, VISS 설정과 ISP DCC 바이트를 `vxCreateUserDataObject`로 전달해 `tivxVpacVissNode`를 구성한다. 먼저 노출·게인을 고정하고 RAW 파일→NV12를 확인한다. 자동화 단계에서는 VISS H3A 통계와 DCC 2A를 `tivxAewbNode`에 제공하고, 결과의 노출·게인을 Linux에서 센서 subdevice 제어로 반영한다. RTOS 센서 제어를 사용하는 SDK 예제의 보드 제어 경로는 Linux 소유 구성에 맞게 대체해야 한다. Imaging 커널 구현과 계약은 필요하며 현재 공유 라이브러리의 심볼을 활용하므로 별도 Imaging 공유 라이브러리 필요성은 ABI 검사로 결정한다. 근거는 `vision_apps/apps/basic_demos/app_single_cam/app_single_cam_common.c`의 VISS 및 AEWB 그래프 생성이다. [TI VPAC ISP 튜닝](https://www.ti.com/lit/an/spracu7a/spracu7a.pdf)

## 5. 미들웨어와 단계별 인수 기준

실기에서 Debian GStreamer 1.26 계열 및 V4L2·app·KMS 플러그인 파일을 확인했다. 조사 범위에서 TI GStreamer 플러그인·TIOVX Modules·GStreamer Apps 설치는 확인되지 않았다. 실행 도구 탐색에서는 `v4l2-ctl`만 확인됐다. 일반 V4L2/GStreamer → Python ORT → DRM/KMS 경로로 USB RGB와 표시를 연결할 수 있고, CSI ISP는 별도 C 그래프에서 연동할 수 있다. `tiovxisp` 등 TI 요소, 기존 Edge AI YAML 데모, 해당 메모리 풀·캡스 협상이 필요할 때 래퍼 도입을 검토한다. 도입 시 PSDK Linux 11.02.00.04의 Yocto 레시피/매니페스트에서 저장소별 정확한 SRCREV를 고정한다. 이번에 Debian 호환 SRCREV는 확정하지 못했다. Modules는 CMake와 SDK 헤더·Vision Apps ABI, Plugins는 Meson 및 GStreamer 개발 패키지·Modules·Apps Utils·필요한 DL 라이브러리, Apps는 Python 및 플러그인/설정 의존성을 검증한다. Debian의 pkg-config 경로, GStreamer/GLib ABI와 TI 라이브러리 검색 경로를 별도 prefix에서 검증한다. [TI Modules](https://github.com/TexasInstruments/edgeai-tiovx-modules) · [TI Plugins](https://github.com/TexasInstruments/edgeai-gst-plugins) · [TI Apps](https://github.com/TexasInstruments/edgeai-gst-apps)

1. **기준선 및 RGB.** 기존 모델 기준 결과와 펌웨어 해시를 보존한다. `lsusb -t`, `v4l2-ctl --list-devices`, `--list-formats-ext`로 컬러 노드를 찾고 고정 모드에서 300프레임을 수집한다. 타임스탬프 진행, 프레임 크기와 오류 여부를 확인한다. Depth/IMU가 필요하면 librealsense에서 세 스트림과 동기화를 별도 시험한다.
2. **소유권 및 DP.** MCU2_0 후보의 오프라인 검사를 먼저 수행하고 기존 noeth 복구 경로를 유지한다. 모니터를 연결해 `/sys/class/drm/card0-DP-1/{status,modes,edid}`와 `modetest -M tidss -c`를 확인한다. 목표 모드가 열거되고 테스트 화면이 안정적으로 표시되면 통과한다. DRM master 또는 장치 접근 권한 실패는 링크 실패와 구분한다.
3. **CSI 및 ISP.** 카메라 오버레이 한 개를 분리된 부트 항목에 시험한다. `media-ctl -p`의 센서→Cadence→TI 캡처 링크, 일치하는 pad/캡처 포맷, 연속 RAW 프레임을 확인한다. 이어 저장 RAW→VISS→NV12, 실시간 VISS, AE/AWB 순서로 시험한다. 부정확한 Bayer 패턴·stride, 색 편향, 노출 진동은 별도로 기록한다.
4. **통합.** 단일 모델부터 다중 모델로 확대하며 프레임 드롭, 지연, CMA 및 heap 사용, RPMsg·remoteproc 상태를 비교한다. 단계마다 기존 추론 정확도와 반복 실행 결과가 유지되어야 한다. 신규 RPMsg timeout, remoteproc 장애, DMA 할당 실패, 메모리 배치 차이가 발견되면 해당 단계에서 중단한다. 사용자가 직전 정상 부트 항목 및 noeth 펌웨어로 복귀할 수 있도록 각각의 변경을 분리한다.
