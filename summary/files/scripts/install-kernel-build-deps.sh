#!/usr/bin/env bash
# Run on a Debian/Ubuntu x86_64 build host.
set -euo pipefail
if [[ $(uname -m) != x86_64 || ! -r /etc/os-release ]]; then
    printf '%s\n' 'Debian/Ubuntu x86_64 빌드 PC에서 실행하세요.' >&2
    exit 1
fi
source /etc/os-release
case "$ID" in
    debian|ubuntu) ;;
    *) printf '%s\n' '지원하는 호스트는 Debian 또는 Ubuntu입니다.' >&2; exit 1 ;;
esac
if (( EUID != 0 )); then
    command -v sudo >/dev/null || { printf 'sudo 필요\n' >&2; exit 1; }
    exec sudo bash "$0" "$@"
fi
apt-get update
apt-get install --yes build-essential git ca-certificates curl flex bison bc     libssl-dev libelf-dev pkg-config gcc-aarch64-linux-gnu     binutils-aarch64-linux-gnu libc6-dev-arm64-cross     kmod xz-utils gzip cpio python3 rsync
aarch64-linux-gnu-gcc --version
aarch64-linux-gnu-as --version
printf '%s\n' '빌드 의존성 설치 완료'
