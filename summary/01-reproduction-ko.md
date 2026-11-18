# 순정 BBAI64 → TIDL 실행 핵심 노트

## 확인된 목표와 구성

Debian을 유지하며 TI ONNX Runtime TIDL EP로 ResNet18 49/49 노드를 오프로딩했다. 워밍업 1회+10회 추론에서 출력 변화 0, CPU 대비 최대 절대오차 0.722227, 평균 target.Run 5.715ms였다. 디버그·호스트 처리 포함 수치이며 제품 성능/전체 정확도/MMA 직접 카운터 검증은 아니다.

| 구분 | 재현 기준 |
|---|---|
| 보드 | BeagleBone AI-64 / J721E(TDA4VM) |
| 순정 이미지 | BeagleBoard Debian Trixie Xfce 2026-07-24, Debian 13.6 |
| 커널 | 6.18.39-arm64-k3-r47, 기준 커밋 c03783811916b255c974912b3fd2eceb30fa8146 → tidl3 |
| SDK | RTOS 11.02.00.06 / 대응 Linux 11.02.00.04 |
| TIDL / MMALIB | Tools 11_02_04_00 / MMALIB 11_02_00_06 |
| 타깃 ORT | **TI 1.15.0**, Debian ORT 1.21과 혼용하지 않음 |
| 펌웨어 | 같은 SDK C71x·C66x 두 개·MAIN R5F 두 개. MCU2_0은 ETHFW=no로 재빌드. 기존 MCU R5F 보존 |
| ORT 설정 | intra/inter-op=1, 순차 실행, spin off |

### 필요한 단계만

1. 순정 보드/부트/DTB가 재현 기준과 같은지 확인하고 SD 복구 수단을 확보한다.
2. 커널 4개 패치를 한 번에 적용하여 tidl3 이미지와 일치 모듈을 빌드한다.
3. BBAI64 보드 DT에 Vision Apps 예약 메모리를 적용한다. EVM DT 전체를 교체하지 않는다.
4. 같은 버전 펌웨어를 배치하되 MCU2_0은 처음부터 noeth판을 사용한다.
5. TI 라이브러리를 별도 폴더에 두고 RPMsg 0.6.11을 프로세스별로 지정한다.
6. 고정 Tools로 생성한 모델·아티팩트·입력 한 세트를 사용한다.
7. DMA → 초기화 → 단일/반복 추론을 검사한다. 실패 단계 이후에는 진행하지 않는다.

중간 tidl1/tidl2, ETHFW를 켠 진단 펌웨어, SIGBUS 재현, endpoint=0 우회 실패를 재현할 필요는 없다.

## 명령 순서

아래는 **현재 검증된 이미지와 GP/비서명 ELF 구성** 기준이다. 호스트와 보드 명령을 구분한다. 원격 실행은 사용자 담당이며 순정 파일 충돌·DTB 불일치를 무시하지 않는다. UART 없이 SSH가 끊기면 SD의 FAT 부트 설정과 Linux 루트의 펌웨어 링크를 다른 PC에서 복구한다.

### A. 호스트: 독립 작업 폴더와 커널

프로젝트 루트에서 시작한다. summary에는 큰 파일을 만들지 않는다.

```bash
cp -a summary/files "$HOME/bbai64-repro"
cd "$HOME/bbai64-repro"
bash scripts/install-kernel-build-deps.sh
mkdir kernel-work
git clone --depth 1 --branch 6.18.39-arm64-k3-r47 \
 https://github.com/RobertCNelson/linux-stable-rcn-ee.git kernel-work/linux
test "$(git -C kernel-work/linux rev-parse HEAD)" = c03783811916b255c974912b3fd2eceb30fa8146
for p in "$PWD"/patches/000[123]-*.patch; do
 git -C kernel-work/linux apply --check "$p" && git -C kernel-work/linux apply "$p" || break
done
bash scripts/prepare-tidl3-kernel.sh
BUILD_JOBS=8 bash scripts/build-tidl3-kernel.sh
(cd kernel-work/stage-tidl3 && sha256sum -c SHA256SUMS)
```

어느 명령이든 오류면 중단한다. prepare가 앞선 패치 합성 결과를 재확인한다. 전체 OS 재생성 없이 커널+모듈만 필요하다. 메모리 여유가 적으면 JOBS=2~4. 빌드는 사용자 수행이며 본 summary 작성 중 실행하지 않았다.

### B. 호스트: SDK 런타임 추출과 최종 noeth 펌웨어

SDK를 외부 경로에 확보한다. 아래 `/실제/경로`를 실제 SDK 경로로 바꾼다. export는 지정 라이브러리/비서명 펌웨어만 읽고 매니페스트 해시를 검사한다. 타 버전은 거부하며 전체 rootfs를 풀지 않는다.

```bash
cd "$HOME/bbai64-repro"
python3 scripts/export-sdk-runtime.py /실제/경로/SDK/tisdk-adas-image-j721e-evm.tar.xz
python3 firmware-work/prepare.py /실제/경로/SDK "$HOME/bbai64-sdk-noeth"
bash firmware-work/build.sh "$HOME/bbai64-sdk-noeth" noeth build
cp "$HOME/bbai64-sdk-noeth/vision_apps/out/J721E/R5F/FREERTOS/release/vx_app_rtos_linux_mcu2_0.out" \
 staging/firmware/vision_apps_evm/vx_app_rtos_linux_mcu2_0.out
```

펌웨어는 TI Arm Clang 4.0.4.LTS를 쓴다. SDK 원본은 수정하지 않는다. noeth 출력의 ELF/map 로드 범위·resource table 검사는 [검증 구현](../bbai64-porting/firmware-work/check-noeth-elf.py)과 [검증 결과](../bbai64-porting/firmware-work/deploy-noeth/noeth-elf-validation.json)를 기준으로 확인한다. 빌드 위치가 달라 전체 파일 해시가 달라도 메모리 검사 없이 승인하지 않는다. 현재 검증된 noeth ELF를 쓰려면 원 프로젝트의 deploy-noeth 파일을 이 staging 경로로 복사하고 해당 SHA256SUMS를 확인한다. 같은 최종 파일을 직접 준비한 경우 펌웨어 재빌드는 생략한다.

### C. 호스트: 보드로 필요한 묶음만 전송

```bash
cd "$HOME/bbai64-repro"
tar -czf "$HOME/bbai64-runtime.tar.gz" scripts src staging rpmsg-work
scp "$HOME/bbai64-runtime.tar.gz" beagle:~/
scp kernel-work/6.18.39-arm64-k3-r47-tidl3-local-package.tar.gz beagle:~/
```

모델은 원 프로젝트의 `tidl/ready/resnet18/` 검증 세트를 사용한다. summary에는 큰 모델을 중복 보관하지 않았다.

```bash
# 호스트 프로젝트 루트에서
(cd tidl/ready/resnet18 && sha256sum -c SHA256SUMS)
ssh beagle 'mkdir -p ~/models/resnet18'
scp -r tidl/ready/resnet18/. beagle:models/resnet18/
```

새로 컴파일하려면 [고정 버전 Docker/공식 모델 절차](../tidl/README-ko.md), [입력/양자화 검증 결과](../tidl/ready/resnet18/README-ko.md)를 사용한다. 양자화·입력/모델/아티팩트 세트를 혼합하지 않는다.

### D. 보드: 설치 준비와 기준 DT 검사

```bash
mkdir -p ~/bbai64-porting
tar -xzf ~/bbai64-runtime.tar.gz -C ~/bbai64-porting
cd ~/bbai64-porting
sudo apt-get update
sudo apt-get install --yes build-essential python3 kmod
bash scripts/01-check-boot-dt.sh --baseline
```

기준 DTB가 다르면 제공 candidate.dtb를 그대로 사용하지 않는다. 현재 부트 DTB에서 메모리 맵을 재통합해야 한다. 같은 기준이면:

```bash
sudo install -m 0644 staging/dt/k3-j721e-bbai64-tidl-candidate.dtb /boot/firmware/ti/
```

### E. 보드: 새 커널·펌웨어·부트 항목

커널 패키지 검사·모듈/이미지 설치 명령은 [tidl3 가이드 2–3번](../bbai64-porting/docs/tidl3-deployment-ko.md)을 따른다. **순정 상태에는 tidl2 항목이 없으므로 그 가이드 4번 자동 생성 코드는 사용하지 않는다.** 대신 아래처럼 수동 항목을 추가한다.

펌웨어 링크에 기존 파일이 있으면 덮어쓰지 말고 대상·백업·복구를 먼저 정한다. 아래는 이름이 비어 있는 재현용 시험 SD 기준이다. MCU R5F 파일은 포함하지 않는다.

```bash
cd ~/bbai64-porting
bash <<'SH'
set -euo pipefail
while read -r name image; do
 [ ! -e "/lib/firmware/$name" ] && [ ! -L "/lib/firmware/$name" ]
done < staging/manifests/firmware-map.tsv
sudo install -d /lib/firmware/bbai64-final-11.02
while read -r name image; do
 sudo install -m 0644 "staging/firmware/vision_apps_evm/$image" /lib/firmware/bbai64-final-11.02/
 sudo ln -s "bbai64-final-11.02/$image" "/lib/firmware/$name"
done < staging/manifests/firmware-map.tsv
SH
sudo cp /boot/firmware/extlinux/extlinux.conf /boot/firmware/extlinux/extlinux.conf.pre-tidl-final
sudoedit /boot/firmware/extlinux/extlinux.conf
```

기존 정상 항목을 남기고 `label tidl-final`을 추가한다. kernel은 `/Image-6.18.39-arm64-k3-r47-tidl3.gz`, fdt는 `/ti/k3-j721e-bbai64-tidl-candidate.dtb`로 지정한다. append는 기존 정상 항목에서 그대로 복사하고 끝에 `bbai64_tidl.entry=tidl-final`을 추가한다. 새 항목에는 fdtdir를 넣지 않는다. default를 tidl-final로 변경한다. 검증 구성의 root는 /dev/mmcblk1p3이고 initrd 지정은 없었다. 다른 구성에서 root를 추측해 변경하지 않는다. initrd가 있으면 실제 부트 파일과 펌웨어 포함 여부를 먼저 확인한다.

설정과 설치한 이미지·DT·모듈을 확인한 뒤 `sync`, `sudo reboot`를 실행한다. 접속이 돌아오지 않으면 SD에서 extlinux.conf.pre-tidl-final을 복원한다. 구형 DT로 돌아가기 전 추가한 5개 펌웨어 링크도 원래 상태로 복구한다. 전체 이미지 백업을 생략해도 이 최소 복구 자료는 보존한다.

### F. 보드: 기능 검사

```bash
uname -r
cat /proc/cmdline
cd ~/bbai64-porting
bash scripts/01-check-boot-dt.sh --entry tidl-final
bash scripts/02-check-remoteproc.sh
sudo bash scripts/03-check-ipc-dma.sh --allocate
sudo env RPMSG_LIB_DIR="$PWD/rpmsg-work/diagnostic-lib" bash scripts/04-check-tidl-runtime.sh --init
sudo env RPMSG_LIB_DIR="$PWD/rpmsg-work/diagnostic-lib" \
 bash scripts/08-check-tidl-repeat.sh \
 "$HOME/models/resnet18/model.onnx" "$HOME/models/resnet18/artifacts/" \
 "$HOME/models/resnet18/input.f32" 1.0
```

03의 호스트 DMA 통과/미검증은 DSP 추론까지 검증하지 않았다는 뜻이다. 04 오류면 추론으로 진행하지 않는다. 08의 종료0·REPEAT_OK·출력비교·매회 benchmark를 확인한다. ORT 단일 스레드가 기본이며 debug 로그가 켜진 시험 구성이다. 전역 Debian 라이브러리를 덮어쓰지 않는다.

## 도구와 남은 작업

호스트 실측: ARM64 GCC 15.2.0, GNU Make 4.4.1, Python 3.14.4, Docker 29.10.0. 이들은 시험 이력이며 모두 필수 고정 버전이라고 단정하지 않는다. 펌웨어 TI Arm Clang 4.0.4.LTS와 모델 Ubuntu22.04/Python3.10/TI ORT1.15/Tools11_02_04_00은 버전 결합 기준이다. 호스트 추가 의존성은 files/scripts/install-kernel-build-deps.sh에 고정된 패키지 목록 참조. 보드 c++/Python3는 설치된 버전을 기록하고 SDK headers와 함께 사용한다.

추가 필요: 깨끗한 SD에서 이 단축 절차 전체 재현, 재부팅/장시간·다중 입력 검증, MMA 직접 프로파일 근거, 제품 정확도·성능 기준. 현재 파일은 성공 구성의 핵심을 모은 것이며 단축 절차 전체를 새 순정 SD에서 재시험한 것은 아니다.
