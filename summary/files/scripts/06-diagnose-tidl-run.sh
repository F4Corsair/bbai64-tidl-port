#!/usr/bin/env bash
# User-run diagnostic; no remoteproc state writes, installation or reboot.
set -euo pipefail
[[ $# == 4 ]] || { echo '인자: model.onnx artifacts input.f32 tolerance'; exit 2; }
(( EUID == 0 )) || { echo 'root로 실행해야 trace/dmesg를 수집할 수 있습니다.'; exit 2; }
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
umask 022
mkdir -p "$PWD/tidl-results"
out=$(mktemp -d "$PWD/tidl-results/run-diag.XXXXXX")
collect() {
 local target="$out/$1"
 mkdir -p "$target"
 uname -a > "$target/kernel.txt"
 for p in /sys/class/remoteproc/remoteproc*; do
  [[ -r $p/name ]] || continue
  if [[ $(cat "$p/name") == 64800000.dsp ]]; then
   cat "$p/name" "$p/state" "$p/firmware" > "$target/c71x-state.txt"
   cat "/sys/kernel/debug/remoteproc/${p##*/}/trace0" > "$target/c71x-trace.txt" 2>"$target/trace-errors.txt" || true
  fi
 done
 ls -l /sys/bus/rpmsg/devices > "$target/rpmsg.txt"
 dmesg > "$target/dmesg.txt" 2>&1 || true
 python3 "$root/scripts/snapshot-shared-log.py" "$target/shared-log" > "$target/shared-log-status.txt" 2>&1 || true
}
collect before
export TIDL_RT_DEBUG=1 BBAI64_TIDL_DEBUG=1
export RPMSG_LIB_DIR="${RPMSG_LIB_DIR:-$root/rpmsg-work/diagnostic-lib}"
export RESULTS_DIR="$out"
if bash "$root/scripts/05-check-onnx-ep.sh" "$@"; then rc=0; else rc=$?; fi
collect after
printf '# TIDL Run 진단\n\n- probe 검사 종료 코드: %s\n- 결과: %s\n- 공유 로그·trace 실패는 각 status/errors 파일 확인\n- 빈 trace는 펌웨어 정상 근거가 아님\n' "$rc" "$out" > "$out/summary.md"
find "$out" -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > "$out/SHA256SUMS"
cat "$out/summary.md"
exit "$rc"
