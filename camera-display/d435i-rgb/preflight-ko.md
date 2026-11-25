# BBAI64 장치 연결 전 점검

[English](preflight-en.md) · [사전 조사](../board-assessment/report-ko.md) · [실기·오프라인 근거](../board-assessment/board-inventory.txt) · [작업 과정](../worklog-ko.md) · [성과](../outcomes-ko.md)

## 완료한 점검

- **D435i.** 실기에서 `v4l2-ctl 1.30.1`, `media-ctl`, libusb, UVC 모듈과 5 Gbit/s USB 버스를 확인했다. SSH 계정은 `video` 그룹에 속한다. HID 센서 허브·가속도·자이로 및 IIO는 모듈로 설정되어 있다. 카메라 노드 접근 권한, 네이티브 Depth/IMU 스트림 및 RSUSB 동작은 연결 후 확인한다. librealsense는 이번 검색 범위에서 발견되지 않았다.
- **IMX219.** 보드의 SK용 DTBO를 읽기 전용으로 가져와 로컬 BBAI64 TIDL 후보 DTB에 `fdtoverlay`로 합성을 시도했다. `vdd_sd_dv`, `csi_mux`, `cam0_i2c`, `cam1_i2c` 참조가 후보 DTB에 없어 `FDT_ERR_NOTFOUND`가 발생했다. 이 오버레이를 적용하지 않는다. BBAI64 CSI1 배선에 맞는 오버레이 후보와 MCU2_0 소유권 처리가 연결 시험의 선행 작업이다.
- **ISP.** SDK 압축 아카이브에서 1920×1080 RAW 샘플과 8/10비트 DCC 후보의 크기·SHA256을 확인했다. SDK `edgeai/edgeai-tiovx-apps/tests/app_tiovx_viss_module_test.c`는 이 RAW를 8비트 컨테이너, MSB 7로 읽어 `VPAC_VISS1`에서 NV12를 생성하고 기본 `dcc_viss.bin`을 사용한다. 해상도별 VISS 두 파일의 해시는 다르고, 조사한 해상도별 2A 두 파일의 해시는 같다. 보드의 Vision Apps 라이브러리 해시는 로컬 staging과 일치한다. 실제 RAW→NV12 실행은 센서 없이 가능한 후속 시험이지만, 현재 범위에서는 보드에 테스트 앱을 빌드·설치·실행하지 않아 그래프 실행과 출력은 미검증이다.
- **MiniDP.** 실행 커널 버전에 대응하는 실기 설정의 `CONFIG_EXTRA_FIRMWARE`에 `cadence/mhdp8546.bin`이 들어 있다. 별도 펌웨어 파일 설치를 전제로 할 근거가 없다. `DP-1` 링크·EDID·화면은 모니터 연결이 가능해질 때까지 보류한다.

## 첫 연결 시험 — D435i RGB

1. D435i를 USB 3 데이터 케이블로 연결한다. 보드에서 `lsusb -t`와 `v4l2-ctl --list-devices`를 실행한다. `5000M` 및 `uvcvideo`를 확인한다. `480M`이면 USB 3 케이블과 포트를 먼저 확인한다.
2. 후보마다 `v4l2-ctl -d /dev/videoN --list-formats-ext`를 실행한다. YUYV 또는 MJPG 등 컬러 포맷을 제공하는 노드와 광고된 해상도·FPS를 선택한다.
3. 사용자가 [시험 스크립트](d435i-rgb-smoke.sh)를 보드에서 실행한다. 아래 모드는 예시이며 실제 노드와 포맷 목록이 우선이다. 스크립트는 USB ID를 확인하고, 협상된 모드를 출력한 다음 60초 이내에 300프레임을 읽어 폐기한다. [RealSense D435i ID 소스](https://github.com/realsenseai/librealsense/blob/master/src/ds/d400/d400-private.h)

   ```bash
   set -o pipefail
   bash d435i-rgb-smoke.sh /dev/videoN 640 480 YUYV 30 2>&1 | tee d435i-rgb.log
   ```

4. 300프레임을 오류 없이 읽고, 요청과 협상된 모드가 일치하며, 프레임 시퀀스 또는 타임스탬프가 연속적으로 진행하면 통과다. 장치 없음, 권한 오류, 포맷 조정, 프레임 누락 또는 시간 초과가 있으면 로그를 보존한다. RGB 기준선 확보 후 Depth·IMU와 카메라→ORT 통합을 별도 시험한다.

스크립트는 로컬 구문 검사 및 잘못된 인수 검사까지 통과했다. 보드의 캡처 ioctl은 카메라 연결 후 사용자가 실행한다.

## 실기 결과 — 1080p30 RGB

사용자가 실행한 [원본 로그](d435i-rgb.log)에서 D435i가 USB 5 Gbit/s와 `uvcvideo`로 연결됐고 V4L2가 1920×1080 YUYV 4:2:2, 30 fps를 협상했음을 확인했다. 301개 dequeue 기록 중 300개가 예상 크기인 4,147,200바이트였다. 시퀀스 0–300은 연속이며, 타임스탬프 간격은 33.346–33.369 ms였다. 시퀀스 52의 버퍼는 1,000,200바이트였고 드라이버가 `error`로 표시했다.

**RGB 캡처 경로 동작 확인. 무오류 기준은 미충족.** 이 로그만으로 단일 오류의 원인을 확정할 수 없다. 같은 모드에서 한 번 더 시험하고 동일 오류가 재현되면 해당 시각의 커널 USB/UVC 로그를 확인한다. 추론 입력은 오류 플래그가 있거나 예상 크기와 다른 YUYV 프레임을 폐기하도록 한다.
