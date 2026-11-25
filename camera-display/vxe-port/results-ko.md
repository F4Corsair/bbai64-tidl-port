# BBAI64 VXE 합성 영상 실기 검증 결과

[English](results-en.md) · [배포 가이드](deployment-ko.md)

**합성 NV12 → VXE H.264 시험 통과.** 사용자 수집 로그에서 `tidl-vxe-test` 부팅과 `img_enc`의 `4200000.video-encoder` 바인딩을 확인했다. 해당 부팅에서 VXE는 `/dev/video1`에 등록됐고 D435i도 별도 노드로 열거됐다.

- GStreamer는 10.0278초에 EOS로 종료됐다. 출력 H.264 파일은 1280×720, 300프레임이며 `ffmpeg -v error -xerror` 전체 디코딩이 통과했다.
- raw H.264에 대한 `ffprobe` FPS 요약값은 서로 달랐다. SPS VUI의 `time_scale=60`, `num_units_in_tick=1`, `fixed_frame_rate_flag=1`과 GStreamer 실행 시간이 30 fps 시험과 일치한다. 수신기 재생 타임스탬프는 아직 검증하지 않았다.
- 수집한 커널 로그에서 VXE timeout이나 DMA 오류는 발견되지 않았다. 별도로 TIDSS runtime PM 경고, `j7-main-r5f1_0-fw`와 `j7-main-r5f1_1-fw` 로드 실패, UVC ROI 제어 비활성화 메시지가 있었다. 이 로그만으로 VXE와의 인과관계를 확정할 수 없다.
- C71x 및 MCU2_0 기동 메시지는 있지만 실제 TIDL 추론 결과가 없어 **TIDL 회귀 판정은 보류**한다. 같은 후보 부팅에서 기존 추론 시험을 먼저 확인한 뒤 D435i YUYV→NV12→VXE 로컬 인코딩을 검증한다. SSH 전송 비교는 그 이후 단계다.

입력 자료는 로컬 `board-results/`의 부트·V4L2·커널·GStreamer 로그와 `vxe-720p30.h264`다. H.264 파일의 SHA256은 `48a7dd97d46b17c1e9c8eb1177d504b28784093821f1eb55489c4aecbbfe4214`다.
