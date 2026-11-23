# TI RPMsg Compatibility-Library Test

Built version0.6.11 from TI commit b1e4d172f39081db81305fa50ccaafd3ef8ae3a6. The official fix replaces failure on unavailable upstream local-endpoint src lookup with a warning/endpoint=0. AArch64 build, exported-symbol equivalence to SDK 0.6.10, SONAME 0, and maximum GLIBC requirement2.38 were checked. One upstream unused-variable warning remains.

The user copies lib and updated04/05 scripts to ~/bbai64-porting. Test with a per-process priority path, not replacement system libraries.

    cd ~/bbai64-porting
    sudo env RPMSG_LIB_DIR="$PWD/rpmsg-work/lib" bash scripts/04-check-tidl-runtime.sh --init

If successful, use the same RPMSG_LIB_DIR for05. At this stage MAIN R5F0_0 lacks port 13 and04 may still fail. Omitting the override uses the original SDK set.

## Remaining IPC conditions

endpoint=0 bypasses lookup failure but does not establish TIOVX round-trip compatibility. ownIpcGetHostPortId in tiovx/source/platform/board/common/tivx_ipc.c forwards appIpcGetHostPortId, so05 must verify remote-node creation and return messages.

MAIN R5F0_0 is running without rpmsg_chrdev.-1.13. SDK vision_apps/platform/j721e/rtos/common/app_init.c calls appEthFwInit under ENABLE_ETHFW before IPC. ETHFW waiting is a possible, not yet confirmed cause. trace0 is root-only and was not read by ordinary-user inspection. The user can provide it with:

    sudo cat /sys/kernel/debug/remoteproc/remoteproc5/trace0

Original04 missed SDK status overwriting after IPC errors. Updated04 also fails on IPC/remote-service error logs. Neither updated04 nor this library had been run on hardware at this stage.
