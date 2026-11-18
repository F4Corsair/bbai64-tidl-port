#!/usr/bin/env bash
set -euo pipefail
# Local-only build; never installs or contacts the board.
[[ $# == 3 ]] || { echo 'usage: bash build.sh PRIVATE_SDK trace|noeth|noboard dry-run|build' >&2; exit 2; }
sdk=$(realpath "$1"); variant=$2; action=$3
[[ -f $sdk/.bbai64-diagnostic-copy ]] || { echo 'Run prepare.py into a fresh directory first.' >&2; exit 2; }
[[ $action == dry-run || $action == build ]] || exit 2
case $variant in
 trace) eth=yes; board=yes;;
 noeth) eth=no; board=yes;;
 noboard) eth=no; board=no;;
 *) exit 2;;
esac
# A configuration must never reuse stale objects from another variant.
if [[ -e $sdk/.bbai64-build-variant ]]; then
 [[ $(cat "$sdk/.bbai64-build-variant") == "$variant" ]] || { echo 'Use a fresh SDK copy for each variant.' >&2; exit 2; }
fi
printf '%s\n' "$variant" > "$sdk/.bbai64-build-variant"
python3 - "$sdk" <<'PY'
import os,pathlib,sys
root=pathlib.Path(sys.argv[1])
for base,ds,fs in os.walk(root,followlinks=False):
 for n in ds+fs:
  q=pathlib.Path(base)/n
  if q.is_symlink() and q.exists() and root not in q.resolve().parents:
   sys.exit('External symlink blocks build: '+str(q))
PY
cc=$sdk/ti-cgt-armllvm_4.0.4.LTS
[[ -x $cc/bin/tiarmclang ]] || { echo 'TI Arm Clang 4.0.4.LTS missing' >&2; exit 2; }
"$cc/bin/tiarmclang" --version
args=(SOC=j721e RTOS=FREERTOS PROFILE=release PSDK_PATH="$sdk" PSDK_TOOLS_PATH="$sdk"
 TIARMCGT_LLVM_ROOT="$cc" BUILD_TARGET_MODE=yes BUILD_EMULATION_MODE=no
 BUILD_CPU_MPU1=no BUILD_CPU_MCU1_0=no BUILD_CPU_MCU2_0=yes BUILD_CPU_MCU2_1=no
 BUILD_CPU_MCU3_0=no BUILD_CPU_MCU3_1=no BUILD_CPU_C6x_1=no BUILD_CPU_C6x_2=no
 BUILD_CPU_C7x_1=no BUILD_LINUX_MPU=yes BUILD_QNX_MPU=no BUILD_APP_RTOS_LINUX=yes
 BUILD_APP_RTOS_QNX=no BUILD_ENABLE_ETHFW="$eth" BUILD_MCU_BOARD_DEPENDENCIES="$board")
extra=(); [[ $action == build ]] || extra=(-n)
# Force rebuilding the changed common library and executable. Dependencies in the
# SDK must already exist; missing archives are a stop condition, not substituted.
make -C "$sdk/vision_apps" "${args[@]}" "${extra[@]}" -B -j"${JOBS:-2}" \
 app_rtos app_rtos_common_mcu2_0 vx_app_rtos_linux_mcu2_0
