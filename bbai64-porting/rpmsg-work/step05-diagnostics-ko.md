# Step 05 사용자 공간 진단판

## 준비 상태

보드 미업로드·실행 미검증. 커널·펌웨어·DT·모델을 바꾸지 않고 다음을 기록한다.

- `PROBE_STAGE`: CPU session, TIDL session, CPU Run, TIDL Run, benchmark 호출 전후의 경과 시간. 출력 버퍼링을 끈다.
- `RPMSG_DIAG request`: rproc, endpoint 이름, 요청 local/remote 주소. `4294967295`는 ANY 요청이다.
- `RPMSG_DIAG src`: sysfs 경로와 원문 값 또는 읽기 오류.
- `RPMSG_DIAG returned`: SDK에 반환하는 local endpoint.
- `PROBE_WRAPPER exit_code`: timeout 124, SIGINT 130 등 종료 코드 구분. 120초 이후 종료되지 않으면 5초 뒤 강제 종료한다. SIGKILL 137은 timeout 강제 종료인지 외부 종료인지 단독 코드로 구분할 수 없다.

**기존 endpoint=0 대체 동작은 유지한다.** 실제 문제를 해결한 라이브러리가 아니라 응답 주소 불일치 여부를 확인하는 진단판이다. 주소를 임의로 고정하지 않는다.

ARM64 라이브러리 빌드, 기존 라이브러리와 공개 심볼 목록·SONAME 일치, 스크립트 문법, 호스트 g++ 기반 probe 문법 검사를 통과했다. 호스트에 ARM64 g++가 없어 probe의 ARM64 링크·실행은 수행하지 않았다. 기존 스크립트처럼 보드 c++로 컴파일한다. 라이브러리는 원본 TI 소스의 unused variable 경고 한 건이 있다.

## 1. 사용자 수동 업로드

```bash
cd /home/corsair/Documents/sdk/ti_sdk_lab
scp bbai64-porting/rpmsg-work/step05-diagnostics.tar.gz beagle:~/
```

묶음에는 새 scripts/05-check-onnx-ep.sh, src/ort-probe.cpp, 별도 rpmsg-work/diagnostic-lib 및 checksum만 있다. 기존 rpmsg-work/lib와 staging/lib는 그대로 둔다.

## 2. 보드에서 이전 검사 파일 보존 후 압축 해제

```bash
cd ~/bbai64-porting
# 이전 백업이 이미 있으면 중단하고 내용을 확인한다.
test ! -e step05-before-diagnostics.tar && \
 tar -cf step05-before-diagnostics.tar scripts/05-check-onnx-ep.sh src/ort-probe.cpp
```

백업이 성공한 경우에만 아래를 실행한다. 위 명령이 실패했다면 자동으로 다음 단계로 진행하지 않는다.

```bash
tar -xzf ~/step05-diagnostics.tar.gz -C ~/bbai64-porting
cd ~/bbai64-porting
sha256sum -c rpmsg-work/step05-diagnostics-SHA256SUMS
```

모든 checksum이 OK여야 한다. 재부팅이나 04 재실행은 필요 없다. 이전 실행이 남아 있다면 그 상태를 먼저 확인하고 동시에 두 추론을 실행하지 않는다.

## 3. 진단 실행

```bash
cd ~/bbai64-porting
sudo env RPMSG_LIB_DIR="$PWD/rpmsg-work/diagnostic-lib" \
 bash scripts/05-check-onnx-ep.sh \
 "$HOME/models/resnet18/model.onnx" \
 "$HOME/models/resnet18/artifacts/" \
 "$HOME/models/resnet18/input.f32" 1.0
```

프로세스가 멈추면 120초 timeout과 최대 5초 종료 유예를 기다린다. 이 제한은 probe에 적용되며 사전 C++ 컴파일 시간은 별도다. 별도 Ctrl-C를 누르면 수동 중단으로 구분한다. 결과에 나온 실제 상세 로그를 읽어 전달한다.

```bash
# 실제 출력된 파일명으로 바꾼다.
sudo cat tidl-results/05-check-onnx-ep.실제이름.log
```

`src raw=-1`과 `returned endpt=0`이 관측되면 요청값 ANY와 실제 응답 주소 조회의 불일치가 강한 후보가 된다. 그래도 실제 kernel endpoint 주소를 측정한 것은 아니므로 주소 문제 확정은 추가 근거가 필요하다. `before tidl_session`에서 끝나면 세션 초기화/원격 노드 생성 경로, `before tidl_run`에서 끝나면 실제 Run 경로를 조사한다. CPU 단계에서 멈추면 RPMsg 원인으로 단정하지 않는다. 실패·중단 시 반복 실행하지 말고 로그를 분석한다.

## 복원

```bash
cd ~/bbai64-porting
tar -xf step05-before-diagnostics.tar
```

이전 명령처럼 RPMSG_LIB_DIR를 rpmsg-work/lib로 지정하면 기존 라이브러리를 사용한다. 새 diagnostic-lib는 시스템 라이브러리를 덮어쓰지 않으므로 삭제할 필요가 없다. 이번 단계에서 보드 시스템 설정이나 펌웨어 변경은 없다.
