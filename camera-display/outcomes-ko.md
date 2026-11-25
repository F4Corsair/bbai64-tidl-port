# BBAI64 카메라·디스플레이 성과

[English](outcomes-en.md) · [계획 및 시행착오](worklog-ko.md)

**D435i RGB 캡처와 VXE 합성 영상 인코딩을 각각 실기에서 확인했다.** 두 경로를 연결한 D435i→VXE 시험과 VXE 후보 부팅의 TIDL 회귀 시험은 아직 확인하지 않았다.

| 작업 | 확인한 성과와 남은 검증 |
|---|---|
| D435i RGB | USB 5 Gbit/s, 1920×1080 YUYV 30 fps를 확인했다. 정상 크기 버퍼 300개와 짧은 오류 버퍼 1개가 기록됐다. [로그 분석](d435i-rgb/preflight-ko.md) |
| 소프트웨어 JPEG 전송 | 사용자 시험에서 축소·JPEG 인코딩 30 fps와 TCP/SSH ProxyJump 전송이 동작했다. 원격 영상 끊김이 남았다. [작업 경과](worklog-ko.md) |
| VXE H.264 | 후보 부팅에서 인코더가 `/dev/video1`에 등록됐다. 합성 NV12에서 1280×720 H.264 300프레임을 생성했고 전체 디코딩을 통과했다. 수집 로그에서 VXE timeout이나 DMA 오류는 발견되지 않았다. [실기 결과 및 커널 경고](vxe-port/results-ko.md) |
| IMX219·VPAC ISP | CSI 모듈과 SDK RAW·DCC 데이터를 확인했다. live CSI 수신기는 비활성 상태였으며, SK 오버레이는 합성에 실패했다. BBAI64용 DT, CSI 소유권, 센서 캡처 및 VISS 실행 검증이 남았다. [보드 지원 조사](board-assessment/report-ko.md) |
| MiniDP | Linux의 `DP-1` 등록과 MHDP 펌웨어 내장 설정을 확인했다. 링크·EDID·실제 출력과 DSS 소유권은 후속 검증 대상이다. [보드 지원 조사](board-assessment/report-ko.md) |

보드를 다시 사용할 수 있을 때 기존 추론 시험을 VXE 후보 부팅에서 실행한다. 통과하면 D435i YUYV→NV12→VXE 로컬 인코딩을 검증한다. 이후 동일 해상도·FPS로 JPEG와 H.264의 CPU 사용률, 전송량, 수신 FPS와 프레임 손실을 비교한다. [VXE 배포 및 검증 절차](vxe-port/deployment-ko.md)

상위 두 보고서는 향후 프로젝트 `docs/`에서 참조할 요약 문서다. 하위 작업 폴더에 상세 절차, 근거 로그와 소스를 둔다. VXE의 생성 바이너리·외부 소스 체크아웃·원시 보드 결과는 기존과 같이 로컬에 보존한다.
