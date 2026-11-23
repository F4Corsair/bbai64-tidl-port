# ETHFW Responsibilities, Disabled Features, and Test Status

## Conclusion

**The ETHFW-disabled firmware has already been built, applied, and passed04.** Read-only SSH on2026-11-18 reconfirmed link bbai64-noeth-mcu2-0/vx_app_rtos_linux_mcu2_0-noeth.out and SHA256 567e257b39a2a6082c8a2394a3e49dea33b5add790449accae6d225f6bb5d695. Saved trace shows IPC rc=0, core synchronization, and remote-service completion. [Evidence](../../docs/bbai64-survey/ethfw-disabled-confirmation-20261118.log)

No rebuild/reupload of the same firmware is needed. Files remain in firmware-work/deploy-noeth/ with a [manual deployment/recovery guide](../firmware-work/deployment-noeth-en.md). board_verified=false in the manifest describes packaging time; later hardware results are recorded separately here and in the failure analysis.

## What ETHFW does

TI Ethernet Firmware runs on J721E MCU2_0 to manage Ethernet-switch resources and provide network services to other cores/OSes. It is not the TIDL compute firmware. SDK integration includes SoC Ethernet/board-port initialization, virtual ports and a MAC-address pool, a remote-configuration server, and configuration-dependent synchronization/routing examples.

Evidence: appEthFwInit, EthFwBoard_init, EthApp_initEthFw, appEthFwRemoteServerInit in sdk_original/vision_apps/utils/ethfw/src/app_ethfw_freertos.c; MAC-pool comments near118, virtual ports near732, conditional gPTP near629, interVLAN near780/1057. Available features depend on build options and board wiring; this does not mean all were in use on BBAI64.

## Impact of disabling it

| Feature | Effect in noeth |
|---|---|
| MCU2_0 ETHFW CPSW virtual-switch/MAC-only ports and remote configuration | Server unavailable; dependent Linux/QNX/RTOS clients cannot use it |
| EVM GESI/QENET Ethernet initialization | ETHFW path does not execute; associated expansion-port support is not provided |
| ETHFW lwIP applications, iperf, etc. | Services from that firmware path are absent; distinguish independent Debian applications |
| ETHFW gPTP/interVLAN/TSN demonstrations | Dependent implementations unavailable; not a blanket disabling of Linux PTP/VLAN |
| BBAI64 Linux eth0/SSH | eth0 uses am65-cpsw-nuss and SSH remained accessible after noeth; all port/load/reboot combinations are not validated |
| USB networking | USB gadget settings unchanged; connection test not performed |
| TIOVX IPC/RPMsg/shared memory | Retained;04 and services confirmed with noeth |
| C71x/MMA TIDL inference | ETHFW is not a direct component of the target function; actual05 inference remains Unverified at this document's stage |
| MCU display/camera board dependencies | BUILD_MCU_BOARD_DEPENDENCIES=yes retained; disabling ETHFW does not remove other EVM dependencies |

## Current changes

- BUILD_ENABLE_ETHFW=no removes MCU2_0 ETHFW early/init/remote-server paths and related link inputs.
- BUILD_MCU_BOARD_DEPENDENCIES=yes retained to avoid changing multiple conditions together.
- Initialization markers and R5F cache-writeback patch retained.
- SDK, DT map, kernel, C71x/C66x/other R5F files unchanged by the noeth test.

Evidence: sdk_original/sdk_builder/vision_apps_build_flags.mak; vision_apps/platform/j721e/rtos/mcu2_0/concerto_mcu2_0_inc.mak; ENABLE_ETHFW sections in rtos/common/concerto.mak and app_init.c; firmware-work/deploy-noeth/build-manifest.json.

## Separate blocker for the next test

At this stage 05 still **times out creating the TIDL session after noeth**. No marker follows before tidl_session; ANY requests yield sysfs src=-1 and SDK endpt=0. Automatic kernel allocation starts at1024, so the returned value is wrong. Disabling ETHFW again cannot fix this.

The next proposed implementation is a user-space RPMsg compatibility patch, not yet prepared at this stage. It requires explicit reservation, correct address return, and collision handling. Do not repeat05 unchanged. No kernel/firmware rebuild is required by that proposed approach; no new RPMsg binary is claimed here. [Failure analysis](rpmsg-failure-analysis-en.md)

## User requirements to check

For Linux networking and TIDL inference, continue from the validated noeth setup. Record separate requirements for other-core ETHFW virtual ports, TSN/gPTP demos, or EVM Ethernet expansion ports. These would require separate BBAI64 ETHFW board support. Preserve .pre-noeth and .pre-trace recovery links.
