# tidl3 RPMsg 응답 주소 호환 패치 — 사용자 빌드 가이드

## 이번 선택과 준비 상태

전체 Debian OS나 루트 파일시스템을 다시 만들 필요는 없다. 이번 수정 대상은 커널의 `rpmsg_char` 드라이버다. 단일 모듈만 같은 tidl2 이름으로 교체하는 방식은 실행 중 endpoint·모듈 의존성과 복구 혼동을 피하기 위해 기본안으로 사용하지 않는다. **새 tidl3 커널 이미지와 일치하는 모듈 세트를 사용자가 빌드**하고 기존 tidl2를 보존하는 방식이다. 소스는 기존 r47 + DMA 0001–0003 패치를 유지한다.

준비 완료: 0004 패치 작성, 독립 kernel-work/linux 작업 소스에 적용, 이전 DMA 패치 합성 결과 일치 검사, git diff --check, out-tidl3/.config 준비, 사용자 빌드·로컬 패키징 스크립트 작성. **커널 컴파일·링크·새 바이너리 생성·보드 업로드·적용은 수행하지 않았다.**

### 왜 사용자 공간 주소 예약 대신 커널 src 노출을 고치는가

자동 요청의 실제 endpoint는 kernel open 시 예약되지만 sysfs src_show는 요청값 chinfo.src=-1을 보여 준다. 라이브러리는 이를 조회 실패로 보고 0을 반환한다. 사용자 공간에서 임의 주소를 선택하는 우회는 충돌 시 open 실패 후 생성 cdev 정리와 재시도가 복잡하다. 커널이 이미 아는 실제 주소를 노출하는 것이 변경 범위가 작고 자동 주소 배정을 그대로 보존한다. 이전에 사용자 공간 수정 가능성을 먼저 제시했으나, 실제 open/실패 정리 경로 검토 후 이 방식을 선택했다.

0004의 src_show는 ept_lock 안에서 열린 endpoint의 ept->addr를 읽고, 열리지 않은 장치에서는 기존 chinfo.src를 보여 준다. open/release/destroy와 같은 잠금으로 포인터 접근을 보호한다. 요청·예약·IPC 메시지 형식은 바꾸지 않는다. 자동 할당은 여전히 커널이 충돌을 처리한다. pre-open ANY는 기존처럼 -1이며 open 후에는 실제 주소를 반환한다.

근거: `drivers/rpmsg/rpmsg_char.c`의 rpmsg_eptdev_open/release, src_show 및 `drivers/rpmsg/virtio_rpmsg_bus.c`의 __rpmsg_create_ept/idr_alloc. 실제 보드 UAPI 호환성·TIDL 세션 통과는 미검증이다. 현재 문제의 유력 원인을 고치는 후보이며 전체 추론 성공을 보장하지 않는다.

## 1. 호스트 준비

프로젝트의 bbai64-porting 폴더를 기준으로 실행한다. 경로를 다르게 옮겼다면 cd만 바꾼다.

```bash
cd /home/corsair/Documents/sdk/ti_sdk_lab/bbai64-porting
# 필요한 호스트 도구가 없을 때만 실행. 호스트 apt 설치를 수행한다.
bash scripts/install-kernel-build-deps.sh
```

기존 tidl2 빌드 환경을 유지했다면 도구를 다시 설치할 필요는 없다. make, ARM64 GCC/binutils, flex, bison, OpenSSL/ELF 개발 헤더, kmod/depmod 등이 필요하다.

## 2. 준비 상태 확인

현재 워크스페이스에서는 준비 스크립트를 이미 실행해 out-tidl3/.config가 있다. **여기서는 다시 실행하지 않는다.** 다른 PC에서 기존 r47/0001–0003 소스를 사용하는 경우 다음을 실행한다.

```bash
bash scripts/prepare-tidl3-kernel.sh
```

이 명령은 기존 DMA 패치 결과와 기준 커밋을 검사하고 0004를 적용한다. 출력 설정이 있으면 덮어쓰기를 거부한다. 소스가 없다면 tidl2 가이드의 2번 소스 준비까지만 진행하고 그 가이드의 빌드 단계는 실행하지 않은 채 이 스크립트를 사용한다. r47 기준 커밋은 `c03783811916b255c974912b3fd2eceb30fa8146`이다. 소스/패치 불일치를 무시하지 않는다.

현재 구성 확인:

```bash
git -C kernel-work/linux diff --check
git -C kernel-work/linux apply --reverse --check \
 "$PWD/patches/0004-rpmsg-char-report-bound-local-endpoint-address.patch"
grep -E '^CONFIG_(RPMSG_CHAR|DMABUF_HEAPS_CARVEOUT|REMOTEPROC_TI_VISION_DMA_BUF)=' \
 kernel-work/out-tidl3/.config
```

기대 설정은 RPMSG_CHAR=m, DMABUF_HEAPS_CARVEOUT=y, REMOTEPROC_TI_VISION_DMA_BUF=y다. 이전 tidl2 출력·배포물은 보존한다. 같은 소스 트리에서 tidl2와 tidl3를 동시에 빌드하지 않는다.

## 3. 사용자가 실제 빌드 실행

```bash
BUILD_JOBS=8 bash scripts/build-tidl3-kernel.sh
```

이 명령부터 커널 빌드가 시작된다. 새 out-tidl3를 사용하므로 전체 빌드 시간이 걸린다. RAM에 맞춰 BUILD_JOBS를 2 또는 4로 낮출 수 있다. 완료 시간은 측정하지 않았다. 진행 로그는 `kernel-work/tidl3-build.log`다.

스크립트는 olddefconfig, 버전/기능 검사, Image.gz와 modules 빌드, **로컬 staging** modules_install, 이미지·설정·System.map·checksum·tar 패키징을 수행한다. modules_install 대상은 프로젝트 내부 stage-tidl3이며 호스트 OS나 보드에 설치하지 않는다. SSH·scp·reboot·모듈 로딩 명령은 없다. DTB는 기존 후보를 유지하므로 다시 만들지 않는다.

오류가 나면 업로드하지 않고 마지막 오류 로그를 전달한다. stage-tidl3가 이미 있으면 스크립트가 멈춘다. 불완전 결과가 있을 때 임의로 성공으로 간주하지 말고 상태를 확인한다. out-tidl3는 빌드 재시도에서 재사용할 수 있다.

## 4. 빌드 후 확인 및 다음 단계

```bash
find kernel-work/stage-tidl3 -name 'rpmsg_char.ko*' -print
(cd kernel-work/stage-tidl3 && sha256sum -c SHA256SUMS)
ls -lh kernel-work/6.18.39-arm64-k3-r47-tidl3-local-package.tar.gz
```

완료 후 tidl3-build.log와 위 확인 결과를 전달한다. 새 이미지·모듈 버전과 패키지를 검토한 뒤 사용자 수동 보드 적용 절차를 확정한다. **아직 존재하지 않는 tidl3 파일을 현재 보드에 적용하지 않는다.** 기존 tidl2 커널·부트 항목과 noeth 펌웨어, SD 복구 수단을 보존한다. 라이브러리는 diagnostic-lib를 그대로 사용해 새 커널에서 raw src/returned endpt가 양수로 일치하는지 검증한다. 라이브러리 재빌드나 모델 재양자화는 필요하지 않다.

최종 단계별 기준:

1. tidl3로 실제 부팅했는지 uname와 부트 표식으로 확인.
2. 기존 heap/ioctl 및 noeth IPC 기능 유지 확인.
3. 같은 Step 05 진단 실행에서 raw src=-1/returned=0이 사라지고 실제 주소가 반환되는지 확인.
4. after tidl_session, after tidl_run, TIDL_BENCHMARK_OK 순서 확인. 새 오류면 다음 단계로 진행하지 않고 로그 분석.
5. 추론 성공 후 별도 C71x/MMA 프로파일 근거 검증.
