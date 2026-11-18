# 작동 설정 고정 및 반복 추론 검증

## 변경과 검증 상태

작동이 확인된 ORT intra/inter-op=1, 순차, spin off를 probe 기본값으로 지정했다. BBAI64_ORT_SINGLE_THREAD=0은 이전 스레딩 비교용으로만 남긴다. 이 문서가 이전 진단 가이드의 기본값 설명을 대체한다.

08은 warm-up 1회 + 측정 10회를 같은 TIDL 세션에서 실행한다. 모든 출력의 shape/유한값/CPU 대비 절대오차와 매 호출 TIDL benchmark 처리 구간을 검사한다. 첫 출력 대비 최대 변화도 기록한다. 출력 변화는 보고값이며 독립 합격 기준을 임의로 두지 않았다. CPU 기준은 같은 입력의 한 번 실행 결과다.

05의 최종 성공은 **기능 검증 성공**으로 한정한다. MMA 직접 증거·제품 정확도·장시간 안정성은 별개라고 명시한다. 이전 코드 2와 기능 실패의 혼동을 줄였다.

로컬 C++ 및 shell 문법 검사·패키지 checksum 준비 완료. 반복 실행의 ARM64 링크·보드 동작은 아직 미검증이다. 120초 제한은 warm-up과 전체 반복 실행에 적용한다. timeout이 나면 반복 횟수를 무작정 늘리거나 연장하지 않고 로그를 검토한다.

## 1. 사용자 업로드 및 백업

호스트 프로젝트 루트에서:

```bash
scp bbai64-porting/rpmsg-work/repeat-validation.tar.gz beagle:~/
```

보드에서:

```bash
cd ~/bbai64-porting
test ! -e before-repeat-validation.tar && \
 tar -cf before-repeat-validation.tar src/ort-probe.cpp scripts/05-check-onnx-ep.sh scripts/06-diagnose-tidl-run.sh
```

백업 성공 후에만 다음을 실행한다.

```bash
tar -xzf ~/repeat-validation.tar.gz -C ~/bbai64-porting
cd ~/bbai64-porting
sha256sum -c staging/manifests/repeat-SHA256SUMS
```

커널·noeth 펌웨어·모델·diagnostic-lib는 유지한다. 재부팅과 strace는 필요 없다.

## 2. 반복 시험

```bash
cd ~/bbai64-porting
sudo env RPMSG_LIB_DIR="$PWD/rpmsg-work/diagnostic-lib" \
 bash scripts/08-check-tidl-repeat.sh \
 "$HOME/models/resnet18/model.onnx" "$HOME/models/resnet18/artifacts/" \
 "$HOME/models/resnet18/input.f32" 1.0
```

기대 결과는 기능 검증 성공과 probe 종료 코드 0이다. 상세 로그에서 ITERATION index=0(warmup)과 index=1..10, REPEAT_OK warmup=1 measured=10을 확인한다. 각 호출의 CPU 오차가 1.0 이하이고 TIDL 처리 구간이 유효해야 한다. 1.0은 연결 시험용이며 모델 전체 정확도 승인 기준은 아니다.

REPEAT_OK의 mean/min/max는 warm-up을 뺀 호스트 target.Run 경과 시간이다. 디버그 출력·CPU 복사·스케줄링을 포함하므로 순수 MMA 시간이나 제품 성능으로 부르지 않는다. 레이어 사이클 및 subgraph 타이밍은 다른 계측값이며 단위 확인 없이 혼합하지 않는다.

실패하면 상세 로그와 실행 전후 C71x 로그를 분석한다. 명령 반복이나 재부팅으로 근거를 지우기 전에 결과를 보존한다. 성공해도 장시간·여러 입력·재부팅 반복성을 검증한 것은 아니다.

## 3. 결과 묶음 및 복구

```bash
# 실제 결과 폴더명으로 변경한다.
sudo tar -czf "$HOME/tidl-repeat-result.tar.gz" \
 -C "$HOME/bbai64-porting/tidl-results" run-diag.실제이름
```

복구:

```bash
cd ~/bbai64-porting
tar -xf before-repeat-validation.tar
```

새 08 스크립트는 복구 후 호출하지 않는다. 보드 설정·커널·펌웨어를 바꾸지 않으므로 재부팅이 필요 없다.

## 가속 증거의 단계

- **기능 확인됨:** 단발 fddW6r에서 실제 Run·출력 비교·TIDL benchmark 및 레이어 사이클을 확인했다.
- **C71x 경로 근거 강함:** 같은 실행의 원격 그래프 생성, C7x heap 처리, TIDL 레이어별 사이클과 출력 반환이 있다. 서비스 존재만으로 판단한 것이 아니다.
- **MMA 직접 검증 미완료:** MMA 특정 명령/하드웨어 카운터·타깃 프로파일의 명시적 대응은 별도 필요하다. 현재 숫자만으로 직접 증명됐다고 선언하지 않는다.

반복 검증이 통과하면 설정을 설치 가이드에 고정하고, 기존 SDK profiler의 MMA 관련 지표를 실제 반환 데이터와 소스로 대조한다. 명시적 지표가 없으면 미확인으로 남기고 제품 정확도/안정성 평가와 분리한다. 이번 준비 단계에서는 보드 업로드·추론 실행을 수행하지 않았다.
