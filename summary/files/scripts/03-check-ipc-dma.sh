#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
board
ls -l /dev/dma_heap/ /dev/remoteproc0 /dev/rpmsg* || true
heap=/dev/dma_heap/carveout_vision_apps_shared-memories
[[ -c $heap ]] || fail 'Vision Apps heap 미노출.'
[[ -r $heap && -r /dev/remoteproc0 && -r /dev/mem && -w /dev/mem ]] || skip 'SDK 장치 접근 권한 확인 필요.'
[[ $(cat /sys/class/remoteproc/remoteproc0/name) == 4d80800000.dsp ]] || fail 'SDK hardcoded remoteproc0의 실기 매핑 변경.'
found=0
for d in /sys/bus/rpmsg/devices/*; do
    [[ $(readlink -f "$d") == *64800000.dsp* ]] && { printf '%s\n' "$d"; found=1; }
done
[[ $found == 1 ]] || fail 'C71x RPMsg 서비스 없음.'
[[ ${1:-} == --allocate ]] || skip '장치 발견. 기능 시험은 승인된 시험 환경에서 --allocate로 실행.'
need cc
probe=$(mktemp -d)
trap 'rm -rf -- "$probe"' EXIT
cc -Wall -Wextra -Werror -O2 "$root/src/dma-probe.c" -o "$probe/dma-probe"
"$probe/dma-probe" || fail 'DMA 할당, 매핑, sync 또는 TI 주소 조회 실패.'
skip '호스트 DMA 기능 통과. DSP 왕복은 04–05에서 실제 추론과 함께 검증하세요.'
