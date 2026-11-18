#!/usr/bin/env bash
set -eu
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
step=$(basename "$0" .sh)
results=${RESULTS_DIR:-"$PWD/tidl-results"}
mkdir -p "$results"
log=$(mktemp "$results/$step.XXXXXX.log")
exec 3>&1
exec >"$log" 2>&1
finish() {
    local status=$1 message=$2 code=$3
    printf '## %s\n\n- 상태: %s\n- 판단: %s\n- 상세 로그: %s\n' \
        "$step" "$status" "$message" "$(basename "$log")" | tee "${log%.log}.md" >&3
    exit "$code"
}
fail() { finish 실패 "$1 다음 단계 중단." 1; }
skip() { finish 미검증 "$1 다음 단계 보류." 2; }
pass() { finish 성공 "$1 다음 단계 진행 가능." 0; }
trap 'fail "명령 실패 (line $LINENO)"' ERR
need() { command -v "$1" >/dev/null || skip "$1 필요."; }
board() {
    [[ $(uname -m) == aarch64 ]] || skip 'AArch64 BBAI64에서 실행해야 합니다.'
    [[ -r /proc/device-tree/model ]] || skip 'live DT 접근이 필요합니다.'
    tr -d '\000' </proc/device-tree/model | grep -q 'BeagleBone AI-64' || fail '대상 보드 불일치.'
}
