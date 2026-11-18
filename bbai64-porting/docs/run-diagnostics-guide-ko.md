# TIDL Run 상세 진단 사용자 실행 가이드

커널 tidl3·noeth 펌웨어·diagnostic-lib·기존 모델은 유지한다. 새 커널/펌웨어 빌드와 재양자화는 이번 진단에 필요 없다. 호스트 모델 재검증은 완료했으며 보드 실행은 사용자 수동이다.

## 업로드와 복구 파일 보존

호스트:

```bash
cd /home/corsair/Documents/sdk/ti_sdk_lab
scp bbai64-porting/rpmsg-work/run-diagnostics.tar.gz beagle:~/
```

보드:

```bash
cd ~/bbai64-porting
# 기존 백업이 있으면 덮어쓰지 말고 먼저 확인한다.
test ! -e run-diagnostics-before.tar && \
 tar -cf run-diagnostics-before.tar src/ort-probe.cpp scripts/05-check-onnx-ep.sh
```

백업 성공 후에만 다음을 실행한다.

```bash
tar -xzf ~/run-diagnostics.tar.gz -C ~/bbai64-porting
cd ~/bbai64-porting
sha256sum -c staging/manifests/run-diagnostics-SHA256SUMS
```

모두 OK여야 한다. 기존 RPMsg diagnostic-lib가 필요하다. 이번 묶음은 라이브러리를 교체하지 않는다.

## 한 번만 진단 실행

```bash
cd ~/bbai64-porting
sudo env RPMSG_LIB_DIR="$PWD/rpmsg-work/diagnostic-lib" \
 bash scripts/06-diagnose-tidl-run.sh \
 "$HOME/models/resnet18/model.onnx" "$HOME/models/resnet18/artifacts/" \
 "$HOME/models/resnet18/input.f32" 1.0
```

TIDL_RT_DEBUG=1과 EP debug_level=1을 설정한다. 실행 전후 C71x 상태/trace, dmesg, RPMsg 목록 및 SDK 공유 로그의 읽기 전용 스냅샷을 수집한다. 공유 로그는 live DT 예약을 확인한 뒤 /dev/mem을 O_RDONLY/PROT_READ로 열며 reader index를 변경하지 않는다. /dev/mem 또는 trace 읽기가 막혀도 설정을 바꾸거나 강제로 우회하지 않고 오류를 기록한다. SDK 제공 app_remote_log는 reader index와 file I/O 상태를 변경할 수 있으므로 이번에 실행하지 않는다.

probe의 120초 제한과 최대 5초 종료 유예를 기다린다. C++ 컴파일·전후 수집 시간은 별도다. 종료 후 결과 디렉터리 `tidl-results/run-diag.XXXXXX`가 출력된다. 실패 코드가 나와도 after 수집을 시도하도록 작성했다. Ctrl-C는 수집을 방해할 수 있어 특별한 사유가 없다면 기다린다.

## 전달할 결과

```bash
# 실제 출력된 디렉터리명으로 변경한다.
sudo tar -czf "$HOME/tidl-run-diag-result.tar.gz" -C "$HOME/bbai64-porting/tidl-results" run-diag.실제이름
```

결과 묶음을 전달하거나 상세 05 로그와 after/shared-log/cpu-*-ring.txt의 C7x 관련 내용을 전달한다. before/after 공유 로그는 실행 중 변화가 있을 수 있는 비원자적 스냅샷이며, 남아 있는 과거 로그와 이번 실행을 시간·인덱스로 대조해야 한다. 빈 C71x trace는 정상 증거가 아니며 cache 가시성이 제한될 수 있다.

로그에서 graph 생성 완료·검증 완료·입력 복사 완료·vxProcessGraph 완료의 마지막 지점을 찾는다. 기존 라이브러리가 충분한 표식을 출력하지 않으면 이 실행 결과를 근거로 런타임의 해당 호출 전후만 추가 계측한다. remote create나 C71x 예외가 확인되면 해당 펌웨어 진단으로 확장한다. 결과 없이 커널 빌드·재양자화·timeout 연장을 반복하지 않는다.

## 되돌리기

```bash
cd ~/bbai64-porting
tar -xf run-diagnostics-before.tar
```

복구 후 05는 이전 probe를 사용한다. 새 수집 스크립트는 호출하지 않으면 동작하지 않으므로 남겨도 된다. 시스템 설정·모듈·펌웨어를 수정하지 않아 재부팅은 불필요하다. 원격으로 Codex가 진단 실행·업로드를 수행하지 않았다.
