# BBAI64 VXE synthetic-input validation results

[한국어](results-ko.md) · [Deployment guide](deployment-en.md)

**Synthetic NV12-to-VXE H.264 test passed.** The collected logs show boot entry `tidl-vxe-test` and `img_enc` bound to `4200000.video-encoder`. VXE registered as `/dev/video1`, and the D435i appeared on separate device nodes.

- GStreamer reached EOS after 10.0278 seconds. The output is 1280×720 H.264 with 300 frames. A full decode with `ffmpeg -v error -xerror` passed.
- The `ffprobe` frame-rate summary fields disagreed for the raw H.264 stream. SPS VUI values `time_scale=60`, `num_units_in_tick=1`, and `fixed_frame_rate_flag=1`, together with elapsed time, support the 30 fps test mode. Receiver playback timestamps remain unverified.
- No VXE timeout or DMA error was found in the collected kernel log. The log separately contains TIDSS runtime PM warnings, missing firmware for `j7-main-r5f1_0-fw` and `j7-main-r5f1_1-fw`, and a disabled UVC ROI control. The log alone cannot establish whether VXE affected those events.
- C71x and MCU2_0 started, but **TIDL regression remains open** pending the actual inference results. Run the existing inference test in the same candidate boot, then validate local D435i YUYV-to-NV12-to-VXE encoding. Compare SSH streaming after the local test passes.

Evidence is in local `board-results/`, including the boot, V4L2, kernel and GStreamer logs and `vxe-720p30.h264`. The H.264 SHA256 is `48a7dd97d46b17c1e9c8eb1177d504b28784093821f1eb55489c4aecbbfe4214`.
