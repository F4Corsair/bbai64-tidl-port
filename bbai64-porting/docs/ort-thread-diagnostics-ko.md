# ORT 단일 스레드 비교 및 대기 위치 진단

## 준비 상태

사용자 공간 probe와 실행 스크립트만 보완했다. 로컬 C++ 문법 검사 및 shell 문법 검사는 통과했다. ARM64 링크·보드 실행은 미검증이며 보드에서 기존처럼 c++로 컴파일한다. 커널·펌웨어·DT·모델·RPMsg 라이브러리는 유지한다. 이 단계는 ORT 스레딩 대기 가능성을 분리하는 시험이며 원인 확정이나 수정 성공을 보장하지 않는다.

새 BBAI64_ORT_SINGLE_THREAD=1 옵션은 CPU/TIDL 두 세션 모두 intra/inter-op=1, 순차 실행, spin 비활성화를 적용한다. 옵션이 없거나 0이면 기존 동작이다. BBAI64_STRACE=1은 timeout 내부에서 probe의 시스템 호출을 수집한다. 기본은 끔이다. 결과의 PROBE_STAGE에 단일 스레드 설정이 표시된다.

## 1. 사용자 업로드

호스트 프로젝트 루트에서:

```bash
scp bbai64-porting/rpmsg-work/thread-diagnostics.tar.gz beagle:~/
```

보드에서 이전 파일 보존:

```bash
cd ~/bbai64-porting
test ! -e before-thread-diagnostics.tar && \
 tar -cf before-thread-diagnostics.tar src/ort-probe.cpp scripts/05-check-onnx-ep.sh scripts/06-diagnose-tidl-run.sh
```

백업 성공한 경우에만:

```bash
tar -xzf ~/thread-diagnostics.tar.gz -C ~/bbai64-porting
cd ~/bbai64-porting
sha256sum -c staging/manifests/thread-diagnostics-SHA256SUMS
```

## 2. 단일 스레드 시험 1회

```bash
cd ~/bbai64-porting
sudo env RPMSG_LIB_DIR="$PWD/rpmsg-work/diagnostic-lib" \
 bash scripts/07-check-ort-threading.sh \
 "$HOME/models/resnet18/model.onnx" "$HOME/models/resnet18/artifacts/" \
 "$HOME/models/resnet18/input.f32" 1.0
```

120초 probe 제한과 최대 5초 종료 유예를 기다린다. 컴파일·로그 수집 시간은 별도다. 결과는 기존처럼 tidl-results/run-diag.XXXXXX에 저장된다. 마지막 PROBE_STAGE와 TIDL_subgraphRtInvoke/Running Graph/TIDL_BENCHMARK_OK 유무를 확인한다. 성공하면 strace 시험은 생략하고 결과를 전달한다. 단일 스레드에서 성공해도 모델 전체 정확도나 성능 검증은 별도다.

## 3. 같은 지점에서 다시 멈춘 경우에만 시스템 호출 수집

보드에 strace가 있는지 먼저 확인한다.

```bash
command -v strace
```

없으면 이 선택 시험을 생략하고 결과를 전달하거나, 사용자가 직접 다음을 실행한다. 이 설치는 필수 커널 변경이 아니라 보드 사용자 공간 도구 설치다.

```bash
sudo apt-get update
sudo apt-get install --yes strace
```

strace가 있으면 다음 한 번만 수행한다. ptrace 기반 관측으로 타이밍이 바뀔 수 있다. 로그가 커질 수 있어 여유 공간을 확인한다. 재부팅·remoteproc 조작·모듈 로딩은 필요 없다.

```bash
cd ~/bbai64-porting
sudo env RPMSG_LIB_DIR="$PWD/rpmsg-work/diagnostic-lib" BBAI64_STRACE=1 \
 bash scripts/07-check-ort-threading.sh \
 "$HOME/models/resnet18/model.onnx" "$HOME/models/resnet18/artifacts/" \
 "$HOME/models/resnet18/input.f32" 1.0
```

같은 결과 폴더의 *.strace.PID가 스레드/프로세스별 기록이다. 마지막 futex만으로 deadlock이라고 단정하지 않는다. 주 스레드와 IPC worker를 구분하고 read/ioctl/poll/futex 및 최종 종료를 대조한다. strace가 권한·도구 오류로 실패하면 보드 보안 설정을 변경하지 말고 오류를 전달한다.

## 4. 결과 전달과 복구

각 실행의 실제 결과 폴더 이름으로 묶는다. 두 번 실행했다면 두 폴더를 모두 보존한다.

```bash
sudo tar -czf "$HOME/ort-thread-result.tar.gz" \
 -C "$HOME/bbai64-porting/tidl-results" run-diag.실제이름
```

기존 방식으로 되돌리기:

```bash
cd ~/bbai64-porting
tar -xf before-thread-diagnostics.tar
```

또는 새 코드에서 BBAI64_ORT_SINGLE_THREAD를 지정하지 않고 05를 실행하면 기존 스레딩이다. 07은 항상 단일 스레드를 설정한다. 새 스크립트는 호출하지 않으면 동작하지 않으며 시스템 설정 복구·재부팅은 필요 없다.
