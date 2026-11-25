# BBAI64 camera and display outcomes

[한국어](outcomes-ko.md) · [Plan and work log](worklog-en.md)

**D435i RGB capture and VXE synthetic-input encoding were verified independently on the board.** Local D435i-to-VXE encoding and the TIDL inference regression on the VXE candidate boot remain open.

| Work item | Outcome and remaining validation |
|---|---|
| D435i RGB | Confirmed USB 5 Gbit/s and 1920×1080 YUYV at 30 fps. The log contained 300 full-size buffers and one short error buffer. [Capture analysis](d435i-rgb/preflight-en.md) |
| Software JPEG streaming | The user reported scaling and JPEG encoding at 30 fps and successful TCP/SSH ProxyJump transport. Remote playback interruptions remain. [Work log](worklog-en.md) |
| VXE H.264 | The candidate boot registered `/dev/video1`. Synthetic NV12 produced 300 decodable 1280×720 H.264 frames. The collected kernel log showed no VXE timeout or DMA error. [Board result and kernel warnings](vxe-port/results-en.md) |
| IMX219 and VPAC ISP | CSI modules and SDK RAW/DCC fixtures are available. The live CSI receivers were disabled and the SK overlay failed to merge. A BBAI64 overlay, CSI ownership, sensor capture and VISS execution remain to be validated. [Board assessment](board-assessment/report-en.md) |
| MiniDP | Confirmed Linux `DP-1` registration and the built-in MHDP firmware setting. Link, EDID, physical output and DSS ownership remain open. [Board assessment](board-assessment/report-en.md) |

When the board is available, repeat the existing inference test under the VXE candidate boot. If it passes, validate local D435i YUYV-to-NV12-to-VXE encoding. Then compare JPEG and H.264 at the same output resolution and frame rate, measuring CPU load, transmitted bytes, received FPS and frame loss. [VXE deployment and validation](vxe-port/deployment-en.md)

The two top-level reports are entry points for a future project `docs/` index. Detailed procedures, evidence and source live in the work folders. Generated VXE binaries, the external source checkout and raw board results remain local.
