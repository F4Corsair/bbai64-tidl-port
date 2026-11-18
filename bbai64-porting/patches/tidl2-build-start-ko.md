# 사용자 PC에서 tidl2 커널 빌드

Debian/Ubuntu x86_64 PC에서 실행한다. BBAI64의 프로그램 설치 단계는 보드 적용 가이드에서 별도로 다룬다. 필요한 파일은 이 `bbai64-porting` 폴더 전체에 들어 있다. 작업 위치를 어디에 두어도 되며 아래 명령은 패키지 루트에서 시작한다.

0003 패치는 주소 조회 시 DMA 설정이 없는 remoteproc 클래스 장치 대신 K3 플랫폼 부모 장치를 사용한다. heap 매핑 오류를 그대로 전달하고 매핑된 attachment에만 캐시 동기화를 수행한다.

## 1. 호스트 프로그램 설치

설치 스크립트는 호스트의 apt 목록을 갱신하고 GCC ARM64 교차 컴파일러, binutils, make, flex, bison 및 커널 빌드 헤더를 설치한다.

```bash
cd /실제/경로/bbai64-porting
bash scripts/install-kernel-build-deps.sh
```

인터넷과 sudo 권한이 필요하다. 배포판이 제공하는 기본 `aarch64-linux-gnu-gcc`를 사용한다. 이전 시험 빌드는 GCC 15였으며, 다른 버전에서 발생하는 경고·오류는 로그로 전달한다. 제공 설정은 Rust가 비활성화된 tidl1 최종 설정을 기준으로 한다. Rust 도구 설치는 필요하지 않다.

## 2. 소스 다운로드와 패치 적용

같은 터미널에서 아래 블록을 실행한다. 소스와 출력은 패키지 아래 `kernel-work/`에 생성한다. 기존 폴더가 있으면 덮어쓰기를 중단하므로 새 작업 경로를 선택하거나 이전 작업의 진행 상태를 먼저 확인한다.

```bash
(
  set -euo pipefail
  package=$(pwd)
  test -f "$package/patches/r47-tidl-build.config"
  work="$package/kernel-work"
  mkdir -p "$work"
  test ! -e "$work/linux"
  git clone --depth 1 --branch 6.18.39-arm64-k3-r47 \
    https://github.com/RobertCNelson/linux-stable-rcn-ee.git "$work/linux"
  cd "$work/linux"
  test "$(git rev-parse HEAD)" = c03783811916b255c974912b3fd2eceb30fa8146
  for patch in "$package"/patches/000[123]-*.patch; do
    git apply --check "$patch"
    git apply "$patch"
  done
  git diff --check
  mkdir -p "$work/out-tidl2"
  cp "$package/patches/r47-tidl-build.config" "$work/out-tidl2/.config"
)
```

소스 커밋과 세 패치의 적용이 확인되면 빌드할 준비가 됐다. 다운로드 또는 패치 적용에서 실패하면 빌드를 시작하기 전에 해당 오류를 해결한다. GitHub 접근이 안 되면 같은 커밋의 소스 아카이브를 확보해 새 소스 디렉터리에 풀고 세 패치를 순서대로 적용한다.

## 3. 이미지와 모듈 빌드

패키지 루트에서 실행한다. 전체 로그는 `kernel-work/tidl2-build.log`에 저장한다. 병렬 작업 수는 기본 8개이며 메모리 여유에 맞춰 `BUILD_JOBS`를 지정할 수 있다. 별도 출력 디렉터리를 사용하므로 재실행하면 완료된 객체를 재사용한다.

```bash
(
  set -euo pipefail
  package=$(pwd)
  source_dir="$package/kernel-work/linux"
  output="$package/kernel-work/out-tidl2"
  export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
  export KBUILD_BUILD_USER=tidl KBUILD_BUILD_HOST=build-pc
  args=(O="$output" LOCALVERSION=-arm64-k3-r47-tidl2)
  cd "$source_dir"
  {
    aarch64-linux-gnu-gcc --version
    make "${args[@]}" olddefconfig
    grep -qx 'CONFIG_DMABUF_HEAPS_CARVEOUT=y' "$output/.config"
    grep -qx 'CONFIG_REMOTEPROC_TI_VISION_DMA_BUF=y' "$output/.config"
    make "${args[@]}" -j"${BUILD_JOBS:-8}" Image.gz modules
    test "$(cat "$output/include/config/kernel.release")" = 6.18.39-arm64-k3-r47-tidl2
    gzip -t "$output/arch/arm64/boot/Image.gz"
  } 2>&1 | tee "$package/kernel-work/tidl2-build.log"
)
```

`make` 실패 시 종료 코드가 유지되며,원인은 로그의 첫 오류와 마지막 부분에서 확인한다. 성공하면 압축 이미지와 모듈이 출력 디렉터리에 생성된다. 보드용 설치 파일 준비를 위해 다음 단계까지 진행한다.

## 4. 로컬 배포 파일 준비

```bash
(
  set -euo pipefail
  package=$(pwd)
  output="$package/kernel-work/out-tidl2"
  release=6.18.39-arm64-k3-r47-tidl2
  stage="$package/kernel-work/module-stage"
  deploy="$package/release/$release"
  test ! -e "$deploy"
  test ! -e "$stage"
  export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
  make -C "$package/kernel-work/linux" O="$output" \
    LOCALVERSION=-arm64-k3-r47-tidl2 INSTALL_MOD_PATH="$stage" \
    INSTALL_MOD_STRIP=1 modules_install
  test -s "$stage/lib/modules/$release/modules.dep"
  rm -f "$stage/lib/modules/$release/build" "$stage/lib/modules/$release/source"
  mkdir -p "$deploy"
  cp "$output/arch/arm64/boot/Image.gz" "$deploy/Image-$release.gz"
  cp "$output/.config" "$deploy/config-$release"
  tar -I 'xz -T2 -3' -cf "$deploy/modules-$release.tar.xz" \
    -C "$stage/lib/modules" "$release"
  cd "$deploy"
  sha256sum Image-*.gz modules-*.tar.xz config-* > SHA256SUMS
  sha256sum -c SHA256SUMS
)
```

이 명령은 PC의 로컬 배포 폴더에 이미지·모듈·설정·해시를 준비한다. 도중 실패하면 부분 생성된 배포 폴더와 module-stage의 파일을 점검한 뒤 재시도한다.

## 전달할 결과와 다음 단계

`kernel-work/tidl2-build.log`의 마지막 40줄, 첫 오류가 있다면 그 주변 로그, `release/6.18.39-arm64-k3-r47-tidl2/SHA256SUMS`를 전달한다. 적용은 [보드 설치 가이드](../docs/r47-kernel-deployment-ko.md)의 시험 부트 절차를 사용하되 **릴리스·이미지·모듈 파일명의 tidl1을 모두 tidl2로 변경**한다. 현재 부팅 중인 정상 tidl1 항목을 복구 대상으로 유지한다.
