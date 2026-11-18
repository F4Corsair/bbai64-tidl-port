#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
unset SKIP_TIOVX_INIT LD_PRELOAD
board
need python3
export LD_LIBRARY_PATH="$root/staging/lib"
if [[ -n ${RPMSG_LIB_DIR:-} ]]; then
    [[ $RPMSG_LIB_DIR == /* && -r $RPMSG_LIB_DIR/libti_rpmsg_char.so.0 ]] ||
        fail 'RPMSG_LIB_DIR에는 라이브러리가 있는 절대 경로가 필요합니다.'
    export LD_LIBRARY_PATH="$RPMSG_LIB_DIR:$LD_LIBRARY_PATH"
fi
python3 - <<'PY'
import ctypes as c
import os
for name in ('libonnxruntime.so.1.15.0', 'libtidl_onnxrt_EP.so', 'libvx_tidl_rt.so'):
    lib = c.CDLL(name, mode=os.RTLD_NOW | os.RTLD_LOCAL)
    print('loaded', name)
    if name == 'libvx_tidl_rt.so':
        for symbol in ('TIDLRT_create', 'TIDLRT_invoke'):
            getattr(lib, symbol)
PY
[[ ${1:-} == --init ]] || skip 'SDK DSO 로딩 성공. 프로세스 초기화는 승인된 시험 환경에서 --init로 실행.'
need timeout
timeout 30s python3 - <<'PY'
import ctypes as c
import os
lib = c.CDLL('libtivision_apps.so.11.2.0', mode=os.RTLD_NOW)
if lib.appInit() != 0:
    raise SystemExit('appInit failed')
if lib.appDeInit() != 0:
    raise SystemExit("appDeInit failed")
print('TIOVX host initialization complete')
PY
if grep -Eq 'IPC init failed|Unable to create TX channels|get_local_endpt failed|Remote service init failed|Perf stats remote service init failed' "$log"; then
    fail 'SDK 오류 로그에서 IPC 또는 원격 서비스 초기화 실패 확인.'
fi
pass 'A72 라이브러리 로딩 및 Vision Apps 초기화 통과. TIDL 노드 검증은 05에서 수행.'
