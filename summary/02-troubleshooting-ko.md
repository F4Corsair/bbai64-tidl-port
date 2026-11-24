# 시행착오와 관련 자료 — 재현할 필요 없는 단계

성공 구성은 [핵심 노트](01-reproduction-ko.md)를 따른다. 아래는 오류가 다시 나왔을 때 찾아볼 기록이다.

| 단계 | 관측 → 필요한 수정 | 상세 자료 |
|---|---|---|
| 버전 식별 | 처음의 11.02.00.07 가정 → RTOS .06/Linux .04/Tools11_02_04_00 확정 | [사전 분석](../docs/psdk-porting-preanalysis-ko.md), [재평가](../bbai64-porting/docs/porting-reassessment-ko.md) |
| DT/코어 | BBAI64 순정 carveout과 SDK ELF 불일치 → 보드 DT에 SDK 맵 통합 | [전략](../docs/bbai64-porting-strategy-ko.md), [후보 맵](files/staging/dt/sdk-memory-map.dtsi) |
| DMA heap | Vision Apps 전용 heap 없음 → 커널0001 | [이식 근거](../bbai64-porting/patches/ti-dma-backport-ko.md) |
| DMA 주소 | ioctl 누락/매핑 실패 → 0002+0003, K3 부모 DMA 장치 사용 | [기존 빌드 설명](../bbai64-porting/patches/tidl2-build-start-ko.md) |
| RTOS 초기화 | MCU2_0 running이나 endpoint13 없음, ETHFW 내부 대기 → noeth | [ETHFW 역할/제한](../bbai64-porting/docs/ethfw-role-and-disable-ko.md) |
| 진단 가시성 | trace가 중간에서 잘림 → R5F cache writeback | [진단판 설명](../bbai64-porting/firmware-work/deployment-trace-wb-ko.md) |
| RPMsg 주소 | src=-1을 라이브러리가0으로 반환, TIDL session 대기 → 커널0004로 실제주소 노출 | [tidl3 패치](files/patches/0004-rpmsg-char-report-bound-local-endpoint-address.patch), [진단 전체](../bbai64-porting/docs/rpmsg-failure-analysis-ko.md) |
| 모델 컴파일 | Docker tivxInit 직후 SIGBUS → shm_size=1gb | [분석](../tidl/sigbus-analysis-ko.md), [Docker](../tidl/compose.yaml) |
| 당시 C++ TIDL Run | 그래프 검증 후 ORT Run 정지. 두 세션의 intra/inter-op을 1로 지정하고 순차 실행과 spinning 비활성화를 적용해 C++ probe가 통과했다. | [단일 스레드 진단](../bbai64-porting/docs/ort-thread-diagnostics-ko.md) |
| 반복 검증 | warm-up1+10회 성공, 출력변화0 → 성공 설정 고정 | [반복 가이드](../bbai64-porting/docs/repeat-validation-ko.md), [재평가](../bbai64-porting/docs/porting-reassessment-ko.md) |

후속 Python 검증에서 포팅된 BBAI64의 TI ORT 1.15.0과 TIDL Tools `11_02_04_00` 공식 Python Wrapper가 통과했다. 직접 만든 Python 세션도 intra-op만 1로 지정하거나 스레드 옵션을 모두 기본값으로 둔 경우에 통과했다. 같은 ResNet18 입력에서 네 케이스가 각각 11/11회 TIDL 추론을 완료했고 출력은 동일했다. [Python 검증 결과](../bbai64-porting/python-ort-validation/results-ko.md)

`running`, `Initialization Done`, RPMsg 장치 존재만으로 추론 성공이라 판단하지 않는다. 초기 04는 SDK가 오류 반환값을 덮어써 오판 가능성이 있었고 현재 스크립트는 오류 로그도 검사한다. 초기 05의 미검증/종료2는 실제 기능 성공과 MMA 증거 미완료를 함께 표현했으며, 현재는 기능 성공과 별도 검증 항목을 구분한다.

기능이 통과한 뒤에는 이미 해결된 오류를 다시 재현하지 않는다. 과거 C++ 정지의 원인과 ETHFW 내부의 정확한 정지 함수, MMA 직접 카운터는 미확인이다. 부팅 시 과거 DSS/Sciclient 오류를 현재 추론 실패로 일반화하지 않는다.
