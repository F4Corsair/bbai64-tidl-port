#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
unset SKIP_TIOVX_INIT LD_PRELOAD
board
[[ $# == 4 ]] || skip '인자: model.onnx artifacts_dir input.f32 abs_tolerance'
[[ -r $1 && -d $2 && -r $3 ]] || skip '모델, 아티팩트 또는 입력 누락.'
need c++
need timeout
export BBAI64_RPMSG_TRACE=1
trap 'finish 미검증 "사용자 중단(SIGINT). 추론 성공/실패 판정 보류." 130' INT
trap 'finish 미검증 "외부 종료(SIGTERM). 추론 성공/실패 판정 보류." 143' TERM
headers="$root/staging/include/onnxruntime/include/onnxruntime/core"
export LD_LIBRARY_PATH="$root/staging/lib"
if [[ -n ${RPMSG_LIB_DIR:-} ]]; then
    [[ $RPMSG_LIB_DIR == /* && -r $RPMSG_LIB_DIR/libti_rpmsg_char.so.0 ]] ||
        fail 'RPMSG_LIB_DIR에는 라이브러리가 있는 절대 경로가 필요합니다.'
    export LD_LIBRARY_PATH="$RPMSG_LIB_DIR:$LD_LIBRARY_PATH"
fi
probe=$(mktemp -d)
trap 'rm -rf -- "$probe"' EXIT
c++ -std=c++17 -O2 -I"$headers/session" -I"$headers/providers/tidl" "$root/src/ort-probe.cpp" \
    -L"$root/staging/lib" -lonnxruntime -o "$probe/ort-probe"
printf 'PROBE_WRAPPER timeout=120s kill_after=5s RPMSG_LIB_DIR=%s\n' "${RPMSG_LIB_DIR:-SDK-default}"
trace_cmd=()
if [[ ${BBAI64_STRACE:-0} == 1 ]]; then
    need strace
    trace_cmd=(strace -ff -tt -T -s 64 -o "${log%.log}.strace")
fi
if timeout --kill-after=5s 120s "${trace_cmd[@]}" "$probe/ort-probe" "$@"; then
    probe_rc=0
else
    probe_rc=$?
fi
printf 'PROBE_WRAPPER exit_code=%s\n' "$probe_rc"
case "$probe_rc" in
    0) ;;
    124) fail '120초 제한 초과. 마지막 PROBE_STAGE와 RPMSG_DIAG 확인.' ;;
    130) finish 미검증 'SIGINT로 중단. 추론 판정 보류.' 130 ;;
    137) fail 'SIGKILL 종료. timeout 강제 종료 또는 외부 종료 여부 확인.' ;;
    143) finish 미검증 'SIGTERM 종료. 추론 판정 보류.' 143 ;;
    *) fail "probe 종료 코드 $probe_rc. 상세 로그 확인." ;;
esac
pass '기능 검증: CPU 출력 비교와 TIDL 처리 타이밍 통과. MMA 직접 사용·제품 정확도·장시간 안정성은 별도 검증.'
