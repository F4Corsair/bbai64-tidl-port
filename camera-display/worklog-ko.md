# BBAI64 카메라·디스플레이 작업 과정

[English](worklog-en.md) · [성과 및 남은 검증](outcomes-ko.md)

기존 Debian 13.6과 `6.18.39-arm64-k3-r47-tidl3`의 TIDL 환경을 기준으로, 카메라 입력과 영상 출력을 한 단계씩 검증했다. 이 문서는 작업을 시작한 이유, 확인한 제약, 다음 경로를 선택한 근거를 기록한다.

## 1. 보드 지원 조사

- 로컬 커널·SDK·펌웨어에서 카메라와 디스플레이 후보를 조사했다. 초기 SSH는 점프 호스트 이름 해석과 배너 교환에서 실패했다. 이후 읽기 전용 실기 조회에 성공해 커널 설정, live DT, 장치 바인딩과 MCU2_0 펌웨어 파일 해시를 대조했다.
- IMX219용 SK 오버레이를 BBAI64 후보 DTB에 오프라인 합성했다. SK의 전원·카메라 I²C 심볼이 없어 `FDT_ERR_NOTFOUND`로 실패했다. BBAI64용 CSI 오버레이와 Linux/RTOS 소유권을 먼저 검토하는 경로로 바꿨다. SDK RAW·DCC와 VISS API는 조사했으며, ISP 그래프는 실행하지 않았다.
- MiniDP는 Linux 바인딩과 MHDP 펌웨어 내장 설정까지 확인했다. 물리 연결 여건에 따라 USB 카메라 시험을 먼저 진행했다. [보드 사전 조사](board-assessment/report-ko.md) · [조회 및 오프라인 근거](board-assessment/board-inventory.txt)

## 2. D435i RGB와 원격 스트리밍

- 기존 V4L2 도구로 USB 3와 RGB 모드를 확인한 뒤 사용자가 1080p30 YUYV 캡처를 실행했다. 버퍼 301개 중 1개가 짧은 오류 버퍼여서 RGB 경로 동작은 확인했지만 무오류 판정은 보류했다.
- 사용자 후속 시험에서 소프트웨어 축소·JPEG 인코딩이 30 fps를 유지했고 TCP/SSH ProxyJump 전송도 이루어졌다. 원격 영상에서 심한 끊김이 있었고 시험한 구성에서 카메라의 MJPEG 직접 출력은 사용할 수 없었다. 인코딩 CPU와 전송량을 줄일 후보로 VXE H.264를 선택했다. 이 단계에서 끊김 원인은 규명하지 않았다. [D435i 시험 절차 및 로그 분석](d435i-rgb/preflight-ko.md)

## 3. VXE 포팅과 후보 부팅

- r47에서 전용 드라이버를 찾지 못해 TI 11.02 이미지의 모듈·DTB·패키지와 비교했다. 처음에는 정확한 소스 리비전을 확인하지 못했으나 meta-ti 릴리스 레시피에서 리비전을 찾아 소스를 확보했다. TI 원본의 V4L2 호환 분기와 내장 MTX 펌웨어를 확인했다.
- 커널 전체를 다시 빌드하는 대신 기존 r47 빌드 출력을 사용하는 외부 모듈을 준비했다. VXE 노드만 추가된 후보 DTB를 오프라인 검증했다. 사용자가 모듈을 빌드하고, 기존 기본 부트 항목을 보존한 채 `extlinux.conf`에 후보 항목을 직접 추가해 합성 입력 시험을 수행했다. [사전 조사](vxe-port/preanalysis-ko.md) · [소스 및 빌드](vxe-port/README-ko.md) · [배포 및 복구](vxe-port/deployment-ko.md) · [실기 결과](vxe-port/results-ko.md)
