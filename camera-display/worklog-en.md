# BBAI64 camera and display work log

[한국어](worklog-ko.md) · [Outcomes and remaining validation](outcomes-en.md)

The work used the existing Debian 13.6 and `6.18.39-arm64-k3-r47-tidl3` TIDL environment as the baseline. This report records the original plan, what blocked it and why the work took its current path.

## 1. Board capability assessment

- Inspected the local kernel, SDK and firmware. Initial SSH attempts failed at jump-host resolution and banner exchange. A later read-only board session confirmed the running configuration, live DT, device binding and MCU2_0 firmware file hash.
- Tried the SK IMX219 overlay offline against the BBAI64 candidate DTB. Missing SK power and camera I²C symbols caused `FDT_ERR_NOTFOUND`. A board-specific CSI overlay and a Linux/RTOS ownership review became prerequisites. Inspected the SDK RAW and DCC fixtures and VISS API. The ISP graph was not run.
- Confirmed Linux MiniDP binding and the built-in MHDP firmware setting. USB camera testing went first while a monitor connection was unavailable. [Board assessment](board-assessment/report-en.md) · [Inventory and offline evidence](board-assessment/board-inventory.txt)

## 2. D435i RGB and remote streaming

- Checked USB 3 and the RGB mode with V4L2. The user ran 1080p30 YUYV capture. One of 301 buffers was short and flagged as an error, leaving the error-free gate open.
- The user subsequently reported software downscaling and JPEG encoding at 30 fps and successful TCP/SSH ProxyJump streaming. Remote playback had severe interruptions, and direct MJPEG was unavailable in the tested setup. VXE H.264 became the candidate for reducing encode CPU and network traffic. The interruption cause was not investigated in this phase. [D435i procedure and log analysis](d435i-rgb/preflight-en.md)

## 3. VXE port and candidate boot

- The r47 tree lacked a dedicated driver. Compared it with TI 11.02 modules, DTBs and packages. The exact source revision initially remained open. The release meta-ti recipe identified it, and source inspection confirmed the V4L2 compatibility branches and embedded MTX firmware.
- Prepared an external module build against the existing r47 output and verified offline that the candidate DTB adds one VXE node. The user built the module, manually added a candidate entry to `extlinux.conf` with the original default preserved, and ran the synthetic-input test. [Feasibility assessment](vxe-port/preanalysis-en.md) · [Source and build](vxe-port/README-en.md) · [Deployment and recovery](vxe-port/deployment-en.md) · [Board result](vxe-port/results-en.md)
