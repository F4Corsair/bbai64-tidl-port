# TI RPMsg 호환 라이브러리 시험

TI 공식 커밋 b1e4d172f39081db81305fa50ccaafd3ef8ae3a6의 0.6.11 소스를 사용했다. upstream 커널에 local endpoint src 속성이 없을 때 실패하던 처리를 경고와 endpoint=0으로 바꾸는 공식 수정이다. AArch64 빌드, SDK 0.6.10 대비 공개 심볼 목록 일치, SONAME 0 및 GLIBC 최대 요구 2.38을 확인했다. 소스의 unused variable 경고 한 건이 있다.

lib 디렉터리와 갱신된 scripts/04-check-tidl-runtime.sh, 05-check-onnx-ep.sh를 사용자가 보드의 ~/bbai64-porting에 복사한다. 시스템 라이브러리 대신 프로세스별 우선 경로로 시험한다.

    cd ~/bbai64-porting
    sudo env RPMSG_LIB_DIR="$PWD/rpmsg-work/lib" bash scripts/04-check-tidl-runtime.sh --init

성공 시 같은 RPMSG_LIB_DIR를 지정하고 05를 실행한다. 현재 MAIN R5F0_0의 포트 13 서비스가 없어 04가 계속 실패할 가능성이 있다. 라이브러리 경로를 지정하지 않으면 기존 SDK 세트로 실행된다.

## 아직 남은 IPC 조건

TI 수정의 endpoint=0은 sysfs 조회 실패를 우회하지만 TIOVX가 host port ID를 사용하는 실제 왕복까지 보장하지 않는다. SDK tiovx/source/platform/board/common/tivx_ipc.c의 ownIpcGetHostPortId는 appIpcGetHostPortId 값을 전달하므로 05의 원격 노드 생성과 반환 메시지를 확인해야 한다.

MAIN R5F0_0은 running이지만 rpmsg_chrdev.-1.13 서비스가 없었다. SDK vision_apps/platform/j721e/rtos/common/app_init.c는 ENABLE_ETHFW의 appEthFwInit을 IPC 초기화보다 먼저 호출한다. 따라서 ETHFW 초기화 대기는 가능성 있는 원인이지만 아직 확정할 수 없다. 해당 코어 trace0는 root 전용이라 일반 사용자 조회로 읽지 못했다. 사용자가 다음 명령으로 기존 trace를 제공하면 초기화가 멈춘 위치를 확인할 수 있다.

    sudo cat /sys/kernel/debug/remoteproc/remoteproc5/trace0

기존 Step 04는 SDK가 IPC 오류 뒤 반환 status를 덮어쓰는 동작을 검출하지 못했다. 갱신본은 IPC 및 원격 서비스 오류 로그도 실패로 처리한다. 이 수정본과 RPMsg 라이브러리는 아직 보드에서 실행하지 않았다.
