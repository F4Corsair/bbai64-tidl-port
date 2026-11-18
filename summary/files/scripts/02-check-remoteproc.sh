#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
board
need sha256sum
declare -A cores=([64800000.dsp]=c7x_1 [4d80800000.dsp]=c6x_1 [4d81800000.dsp]=c6x_2 [5c00000.r5f]=mcu2_0 [5d00000.r5f]=mcu2_1)
seen=0
mcu=0
for r in /sys/class/remoteproc/remoteproc*; do
    [[ -r $r/name ]] || continue
    name=$(cat "$r/name")
    state=$(cat "$r/state")
    fw=$(cat "$r/firmware")
    printf '%s %s %s %s\n' "$r" "$name" "$state" "$fw"
    if [[ $name == 41000000.r5f && $state == attached ]]; then mcu=1; fi
    [[ -n ${cores[$name]:-} ]] || continue
    [[ $state == running ]] || fail "$name 상태 $state."
    [[ $fw != */* && -r /lib/firmware/$fw ]] || fail "$name firmware 조회 실패."
    base="$root/staging/firmware/vision_apps_evm/vx_app_rtos_linux_${cores[$name]}.out"
    cmp -s "/lib/firmware/$fw" "$base" || cmp -s "/lib/firmware/$fw" "$base.signed" || fail "$name firmware 해시 대상 불일치."
    sha256sum "/lib/firmware/$fw"
    seen=$((seen+1))
done
(dmesg | grep -Ei 'remoteproc|rpmsg|request_firmware') || true
[[ $seen == 5 && $mcu == 1 ]] || fail 'Vision Apps 코어 5개와 기존 MCU attach 확인 필요.'
pass '코어 기동 및 현재 펌웨어 파일 확인. IPC 시험 필요.'
