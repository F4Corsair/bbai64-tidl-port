#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
board
uname -a
cat /proc/cmdline
cat /proc/sys/kernel/random/boot_id
findmnt /
findmnt /boot/firmware
if [[ ${1:-} == --baseline ]]; then
    sha256sum /boot/firmware/ti/k3-j721e-beagleboneai64.dtb
    sha256sum "$root/staging/dt/base-survey.dtb"
    cmp /boot/firmware/ti/k3-j721e-beagleboneai64.dtb "$root/staging/dt/base-survey.dtb" || fail '수집 기준 DTB와 달라 재검토 필요.'
    pass '부트 파티션의 기준 DTB 파일 일치. 실제 엔트리는 별도 확인 대상입니다.'
fi
case ${1:-} in
    --entry)
        [[ $# == 2 && $2 =~ ^[A-Za-z0-9._-]+$ ]] || skip '사용법: --entry TAG'
        read -r -a bootargs </proc/cmdline
        entries=()
        for arg in "${bootargs[@]}"; do
            [[ $arg != bbai64_tidl.entry=* ]] || entries+=("$arg")
        done
        [[ ${#entries[@]} == 1 && ${entries[0]:-} == "bbai64_tidl.entry=$2" ]] ||
            fail "부트 마커 bbai64_tidl.entry=$2 불일치 또는 중복."
        printf 'boot entry marker: %s\n' "${entries[0]}"
        ;;
    '') ;;
    *) skip '사용법: --baseline 또는 --entry TAG' ;;
esac
need python3
PYTHONDONTWRITEBYTECODE=1 python3 "$root/scripts/check-live-dt.py" "$root/staging/dt/k3-j721e-bbai64-tidl-candidate.dtb"
pass 'live DT의 후보 메모리와 코어 참조 확인.'
