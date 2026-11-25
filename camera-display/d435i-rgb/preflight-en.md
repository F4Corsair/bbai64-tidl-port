# BBAI64 checks before connecting hardware

[한국어](preflight-ko.md) · [Feasibility assessment](../board-assessment/report-en.md) · [Board and offline evidence](../board-assessment/board-inventory.txt) · [Work log](../worklog-en.md) · [Outcomes](../outcomes-en.md)

## Completed checks

- **D435i.** The board has `v4l2-ctl 1.30.1`, `media-ctl`, libusb, the UVC module and a 5 Gbit/s USB bus. The SSH account is in the `video` group. The HID sensor hub, accelerometer, gyroscope and IIO are configured as modules. Node permissions, native depth and IMU streaming, and RSUSB remain connection-time checks. The inventory did not find librealsense.
- **IMX219.** The board's SK DTBO was copied read-only and applied offline to the local BBAI64 TIDL candidate DTB with `fdtoverlay`. The merge failed with `FDT_ERR_NOTFOUND` because the base lacks `vdd_sd_dv`, `csi_mux`, `cam0_i2c` and `cam1_i2c`. Keep this overlay out of the boot configuration. A BBAI64 CSI1 overlay candidate and resolution of MCU2_0 ownership are prerequisites for a connection test.
- **ISP.** Checked size and SHA256 for the SDK's 1920×1080 RAW fixture and matching 8/10-bit DCC candidates. SDK test `edgeai/edgeai-tiovx-apps/tests/app_tiovx_viss_module_test.c` uses this fixture with an 8-bit container, MSB 7, default `dcc_viss.bin`, and `VPAC_VISS1` to produce NV12. The resolution-specific VISS variants differ by hash. The two inspected resolution-specific 2A variants match by hash. The board's Vision Apps library matches local staging by hash. Running RAW-to-NV12 on the board can be done without a sensor. Graph execution and output remain unverified because this assessment excluded preparing and deploying a test application to the board.
- **MiniDP.** The board's config for the running kernel version includes `cadence/mhdp8546.bin` in `CONFIG_EXTRA_FIRMWARE`. There is no evidence that a separate firmware install is required. DP link, EDID and scanout tests are deferred until a monitor can be connected.

## First connection test — D435i RGB

1. Attach the D435i with a USB 3 data cable. On the board, use `lsusb -t` and `v4l2-ctl --list-devices`. Check for `5000M` and `uvcvideo`. If the link reports `480M`, check the cable and port first.
2. Run `v4l2-ctl -d /dev/videoN --list-formats-ext` for each candidate. Pick the node with color formats such as YUYV or MJPG and select an advertised mode.
3. Run the [smoke-test script](d435i-rgb-smoke.sh) on the board. The command below is an example. Substitute the actual node and advertised mode. The script checks the USB ID, prints the negotiated mode, and captures 300 frames to the null device with a 60-second limit. [RealSense D435i ID source](https://github.com/realsenseai/librealsense/blob/master/src/ds/d400/d400-private.h)

   ```bash
   set -o pipefail
   bash d435i-rgb-smoke.sh /dev/videoN 640 480 YUYV 30 2>&1 | tee d435i-rgb.log
   ```

4. Pass when 300 frames arrive without errors, the negotiated mode matches the request, and frame sequence or timestamps progress consistently. Keep the log for missing nodes, permission failures, format adjustment, frame drops or timeouts. Test depth/IMU and camera-to-ORT integration separately once RGB passes.

The script passed local syntax and invalid-argument checks. The user runs the capture ioctls after attaching the camera.

## Board result — 1080p30 RGB

The user's [capture log](d435i-rgb.log) shows a 5 Gbit/s USB connection with `uvcvideo` and a negotiated V4L2 mode of 1920×1080 YUYV 4:2:2 at 30 fps. Of 301 dequeued buffers, 300 had the expected 4,147,200 bytes. Sequence numbers 0–300 were consecutive and timestamp intervals were 33.346–33.369 ms. The driver marked sequence 52 as `error` with a short payload of 1,000,200 bytes.

**RGB capture worked. The error-free acceptance criterion remains open.** The log alone does not establish the cause of the single error. Repeat the same mode and check the kernel USB/UVC log around any recurrence. Drop error-marked or incorrectly sized YUYV frames before passing them to inference.
