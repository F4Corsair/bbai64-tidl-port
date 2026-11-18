# 수동 배치 및 단계별 검증

## 1. 원본과 복구

플래시 직후이고 보존할 데이터가 없다면 전체 백업은 생략한다. UART가 없으므로 SSH가 돌아오지 않을 때 SD를 다른 PC에서 편집하거나 원본 이미지를 다시 플래시할 수 있어야 한다. 필요하면 전체 이미지 대신 extlinux.conf만 다른 PC에 복사한다.

    sha256sum -c staging/manifests/SHA256SUMS
    bash scripts/01-check-boot-dt.sh --baseline
    findmnt -no SOURCE,TARGET /boot/firmware
    cat /proc/sys/kernel/random/boot_id

기준 DTB 비교는 후보 생성에 사용한 파일과 부트 파티션의 파일이 같은지 확인한다. 해시가 다르면 현재 DTB를 다시 수집해 후보를 재검토한다.

## 2. DT 배치와 시험 부트 항목

기본 BBAI64 DT의 C71x 펌웨어 영역은 0xa8100000에서 시작하고 Vision Apps ELF는 0xb2100000을 사용한다. 후보 DTB는 수집한 BBAI64 DTB의 보드 설정 위에 코어별 carveout과 공유 영역을 반영한 완성된 트리다. BBAI64 전용 DTBO로도 같은 변경을 표현할 수 있다. 기존 예약 영역 비활성화, 새 영역과 phandle을 모두 반영하고 U-Boot의 fdtoverlays 지원 및 병합 결과를 검증해야 한다. TI EVM DTBO는 보드 심볼과 ETHFW 참조가 달라 비교에 사용한다.

    sudo install -m 0644 staging/dt/k3-j721e-bbai64-tidl-candidate.dtb /boot/firmware/ti/
    sudoedit /boot/firmware/extlinux/extlinux.conf

정상 항목을 복제해 label tidl-test를 만든다. kernel, append 및 필요한 initrd는 복제하고 시험 항목의 fdtdir는 제거한다. 시험 항목에 fdt /ti/k3-j721e-bbai64-tidl-candidate.dtb를 지정한다. 기존 **append 줄 끝**에 bbai64_tidl.entry=tidl-test-v1을 한 번 추가한다. 전역 default를 **default tidl-test**로 지정한다. 마커는 시험 항목에만 넣고 설정 버전을 구분할 때는 새 태그를 사용한다.

## 3. 커널 소스 없이 확인할 범위

exporter는 SDK가 여는 이름의 DMA heap을 제공하고, RPROC_IOC_DMA_BUF_ATTACH는 SDK가 할당된 버퍼 주소를 얻는 데 사용한다. 이 기능은 SDK 추론 경로에 필요하지만, 후보 DT 부팅이나 코어·RPMsg 열거를 확인하는 전제는 아니다.

TI Git 확인을 생략하고 현재 커널로 진행한다. 먼저 펌웨어를 추가하지 않고 5단계의 부트 마커와 live DT를 확인한다. 이후 4단계에서 펌웨어를 배치하고 다시 부팅해 코어 상태를 확인한다. 6단계에서 필요한 heap과 ioctl이 실제로 동작하는지 검사한다. heap이 없거나 주소 조회가 실패하면 DMA를 사용하는 초기화와 추론만 보류한다. 일반 CMA 장치 이름을 바꾸는 것으로 SDK 주소 계약을 대신할 수 없다.

## 4. 펌웨어 배치

후보 DT로 부팅한 뒤 다섯 코어의 요청 이름과 GP/HS 로더 요구를 확인한다. 이 단계는 펌웨어 검색·로딩과 코어 초기화를 검증하기 위한 것이다. 아래 명령은 **비서명 ELF가 요구된다고 확인된 경우**의 예다. 서명 변형은 로더가 요구하는 실제 이름과 파일을 확인해 별도로 연결한다.

```bash
sudo install -d /lib/firmware/bbai64-psdk-11.02
while read -r name image; do
  if [ -e "/lib/firmware/$name" ] || [ -L "/lib/firmware/$name" ]; then
    printf '기존 펌웨어 충돌: %s\n' "$name" >&2
    exit 1
  fi
done < staging/manifests/firmware-map.tsv
(
  set -e
  while read -r name image; do
    sudo install -m 0644 "staging/firmware/vision_apps_evm/$image" /lib/firmware/bbai64-psdk-11.02/
    sudo ln -s "bbai64-psdk-11.02/$image" "/lib/firmware/$name"
  done < staging/manifests/firmware-map.tsv
)
```

다섯 링크와 실제 파일을 확인한다. MCU 링크는 그대로 둔다. 배치 중 오류가 나면 시험 SD에서 추가한 링크만 확인해 제거하고 원본 부트 구성을 사용한다. 시험 DT와 펌웨어는 함께 적용·복구한다.

## 5. 시험 부팅과 코어 상태

사용자가 수동으로 재부팅한 뒤 SSH에서 실행한다.

    cat /proc/sys/kernel/random/boot_id
    bash scripts/01-check-boot-dt.sh --entry tidl-test-v1
    # 펌웨어 배치 후 다시 부팅한 경우에만
    bash scripts/02-check-remoteproc.sh

부트 ID가 바뀌면 새 부팅이다. 마커는 커널 명령줄로 전달된 항목을, live DT 검사는 후보의 예약 영역과 phandle을 확인한다. 마커가 없으면 읽는 부트 파티션과 실제 extlinux 설정을 확인한다. 마커가 맞고 DT가 다르면 fdt 경로를 확인한다. 이미 마커 없이 부팅했다면 인자 없이 01을 실행해 live DT를 확인할 수 있다.

SSH가 돌아오지 않으면 SD를 다른 PC에서 열어 정상 항목을 기본값으로 복원한다. 펌웨어 배치 후 구형 DT로 돌아갈 때는 시험용 펌웨어 링크도 오프라인에서 제거한다. FAT 파티션만 수정할 수 있다면 원본 SD 또는 재플래시를 사용한다.

## 6. IPC와 DMA

장치 열거와 DMA 할당·매핑·주소 조회의 실제 동작을 구분한다.

```bash
bash scripts/03-check-ipc-dma.sh
sudo bash scripts/03-check-ipc-dma.sh --allocate
```

첫 실행은 장치와 endpoint를 조회한다. 두 번째는 시험 환경의 승인된 사용자만 실행하고 `cc`와 Linux UAPI 헤더가 필요하다. 4 KiB 임시 버퍼 할당·mmap·캐시 sync·TI 주소 ioctl을 수행한다. 주소 범위 또는 ioctl 실패 시 ABI/DT/권한을 조사하고 추론을 중단한다. `DMA_HOST_OK`까지 나오고 상태가 미검증이면 호스트 부분만 통과한 것이다. 이후 C71x를 실제 사용하는 추론으로 공유 데이터 경로를 확인한다.

## 7. 격리 런타임

Debian ORT와 TI ORT 혼용을 피하고 TIOVX 초기화 오류를 분리한다.

```bash
sudo install -d /opt/bbai64-porting
sudo cp -a scripts src staging /opt/bbai64-porting/
cd /opt/bbai64-porting
RESULTS_DIR="$HOME/tidl-results" bash scripts/04-check-tidl-runtime.sh
sudo env RESULTS_DIR=/var/tmp/tidl-results bash scripts/04-check-tidl-runtime.sh --init
```

전역 라이브러리와 로더 설정은 보존한다. 로딩 또는 `appInit` 실패 시 로그에서 SONAME/undefined symbol, DMA, IPC 초기화 위치를 확인하고 다음 단계로 넘어가지 않는다. 성공 시 TI 런타임 초기화가 완료된다. 철회 시 시험 SD에서 격리 디렉터리만 제거한다.

## 8. 모델 준비 및 ONNX EP

같은 입력에서 CPU와 EP 출력을 비교한다.

x86_64 작업 환경에서 [TI 태그 고정 예제](https://github.com/TexasInstruments/edgeai-tidl-tools/tree/11_02_04_00#running-on-x86-pc)를 사용한다. 공급사 예제 설정에서 단일 입력·출력, 고정 shape의 float32 ONNX 모델을 선택한다. 호스트 번들의 `versions.txt`가 J721E 및 요청 릴리스와 일치해야 한다.

```bash
git clone --branch 11_02_04_00 https://github.com/TexasInstruments/edgeai-tidl-tools.git
cd edgeai-tidl-tools
./scripts/setup/setup.sh
source ./scripts/setup/setup_env.sh J721E
cd runtimes/examples/python/basic_example
python3 basic_example.py --config ./config.yaml -r onnxrt --compile
```

출력된 모델 파일과 **해당 모델의 아티팩트 디렉터리 전체**를 사용한다. 최적화로 모델 파일이 바뀌면 아티팩트를 생성한 파일을 고정한다. 입력은 모델의 shape/전처리에 맞춘 little-endian float32 연속 배열을 `numpy.asarray(input_tensor, dtype='<f4').tofile('input.f32')`로 저장한다. 허용오차는 모델의 양자화 정확도 기준으로 실행 전에 정한다. `c++`가 있는 시험 보드에서 실행한다.

```bash
sudo env RESULTS_DIR=/var/tmp/tidl-results bash scripts/05-check-onnx-ep.sh \
  /path/to/model.onnx /path/to/model-artifacts /path/to/input.f32 0.05
```

`0.05`는 절대오차 예시다. 모델, 아티팩트와 입력은 사용자가 시험 매체에 배치한다. 스크립트는 SDK ORT로 임시 실행기를 빌드하고 CPU 결과와 TIDL 경로의 결과 및 서브그래프 처리 시간을 비교한다. 아티팩트 형식 또는 provider 오류가 나면 같은 태그로 모델을 재생성하고 라이브러리 경로를 점검한다.

## 9. C71x/MMA 확인

출력이 일치해도 CPU fallback일 수 있으므로 하드웨어 실행 증거를 확인한다.

`TIDL_BENCHMARK_OK`와 1개 이상의 처리 구간을 확인하고 같은 실행의 C71x 펌웨어 프로파일·MMA 실행 근거를 수집한다. CPU fallback 또는 프로파일 부재는 최종 미검증이다. 실패하면 같은 모델·입력·아티팩트를 유지하고 첫 실패 단계의 로그부터 검토한다. [결과 양식](validation-results-template-ko.md)에 해시, 부트 정보와 Markdown/상세 로그를 함께 기록한다.
