# BBAI64 TIDL 포팅 가능성·양자화 재평가

## 결론

**권장: 현재 Debian을 유지하며 조건부로 계속 진행한다.** 공식 버전 조합과 호스트 모델 실행은 확인됐고, 포팅 수정마다 DMA·IPC·TIDL session 생성으로 검증 범위가 확장됐다. 현재 장애는 첫 TIDL Run 내부로 좁혀졌지만 graph verify/remote create/process 중 어느 호출인지는 미확인이다. Debian 13이라 불가능하다고 판단할 근거는 없다. 반대로 공식 지원 환경과 동일하거나 양산 사용 가능하다고 볼 근거도 없다.

다음 한 번의 상세 진단 후 수정할 구성요소를 결정한다. 사용자 승인을 반영해 런타임/C71x 재빌드까지 검토할 수 있지만, 관측 없이 모두 다시 빌드하지 않는다.

## 핵심 이력과 현재 상태

- DMA heap exporter 및 TI 주소 조회 호환 기능을 이식해 호스트 버퍼 경로 확보.
- EVM용 ETHFW 초기화에서 진행되지 않던 MCU2_0을 noeth로 구성해 IPC·코어 동기화·원격 서비스 등록 및 Step 04 통과.
- tidl3의 RPMsg 실제 주소 노출 수정 후 raw=-1/반환0 대신 1026/1027 일치, TIDL session 생성과 CPU Run 통과.
- 최신 SmOQ5M에서는 before tidl_run 뒤 120초 timeout. CPU/TIDL 출력 비교·MMA 성공 근거는 없다.

근거: 기존 `rpmsg-failure-analysis-ko.md`, `docs/bbai64-survey/step05-SmOQ5M-user.log` 및 `reassessment-board-20261118.log`.

## 버전과 Debian에서의 제약

| 영역 | 판정 | 근거와 한계 |
|---|---|---|
| RTOS 11.02.00.06 / Linux 11.02.00.04 / TIDL 11_02_04_00 | 확인됨 | TI J721E 구성 문서의 대응 버전. 호스트 이미지 커밋은 bb029fb79929e0fc0c2c13d2d40b13237eabbca1 |
| Debian 13.6 / GLIBC 2.41 / r47-tidl3 | 확인됨·일부 기수집 | 이번 SSH는 tidl3와 GLIBC 2.41 확인. Debian 세부 버전은 기존 실기 자료에 근거 |
| 사용자 공간 ABI | 실행된 경로 확인됨 | TI ORT 1.15 로딩·세션 생성·CPU Run 성공. libvx_tidl_rt/ORT 보드 해시가 로컬과 일치. 모든 지연 로딩 심볼·경로까지 검증한 것은 아님 |
| 커널 DMA/IPC | 일부 확인됨 | 할당·주소 조회·endpoint 반환과 초기화 성공. 실제 C71x 소비 주소/캐시 일관성·descriptor 왕복 완료는 미확인 |
| SYSFW/자원 배분·부트 체인 | 미확인 항목 남음 | 현재 부트 체인을 유지함. Sciclient 성공만으로 SDK의 모든 DMA/IRQ/MMA 자원과 동일하다고 단정 불가 |
| C71x 타깃과 TIDL/MMALIB | 버전 세트 근거 있음·실행 미검증 | SDK 펌웨어를 사용하지만 첫 Run 완료는 없음. 예외·heap·타깃 생성·버퍼 가시성 조사 필요 |

공식 문서는 Processor SDK Linux 기반을 전제로 한다. Debian 배포판명 자체보다 TI 커널 UAPI·메모리/캐시·자원 배분·펌웨어와 런타임의 결합이 핵심 차이다. OS 전환이나 TIDL 버전 혼합은 현재 기본안이 아니다.

## 모델·양자화 독립 재검증 결과

2026-11-18 고정 Docker `bbai64-tidl:11_02_04_00-j721e`(이미지 a8a10cfd1bfb)에서 원본 자료를 읽기 전용으로 마운트하고 별도 artifacts 복사본으로 재실행했다. 기존 산출물을 덮어쓰지 않았다. onnx.checker 검사도 통과했다.

| 검사 | 결과 |
|---|---|
| ORT / 대상 | 1.15.0 / J721E, TIDLExecutionProvider 존재 |
| 모델·입력·net/io/meta 파일 보드 해시 | 로컬 ready 세트와 모두 일치 |
| 공식 전처리 재생성 | 기존 input.f32와 바이트 단위 동일 |
| 입력 | RGB 로더·NCHW [1,3,224,224]·little-endian float32, 602112바이트 |
| CPU/호스트 TIDL 출력 | [1,1000], 모두 유한값 |
| 최대 절대오차 / RMSE | 0.72222900390625 / 0.1836877697153177 |
| top-1 index | CPU=895, TIDL=895 |
| 이전 저장 CPU/TIDL 출력 대비 최대 차이 | 각각 0.0 / 0.0 |

평가 스크립트는 `tidl/scripts/reassess-resnet18.py`, 로그는 `tidl/logs/reassessment-host.log`, 측정값·해시 대조는 `tidl/reassessment/results.json`, `board-hash-comparison.json`이다. 공식 basic DatasetLoader/PreProcess와 저장 config를 사용했다. 컴파일 옵션은 8-bit, calibration_frames=2, iterations=5다. 공식 예제의 해당 설정과 원본 컴파일 로그를 보존했다.

**판단:** 잘못된 파일 배포·전처리 불일치·호스트에서 전혀 실행되지 않는 양자화 산출물이라는 가설은 이번 증거와 맞지 않는다. 따라서 재양자화를 지금 우선하지 않는다. 다만 두 보정 프레임과 한 입력 비교는 정확도 검증이 아니다. 호스트 에뮬레이션 성공도 C71x 전용 코드 생성·MMA·온보드 메모리 요구조건의 정상 동작을 보장하지 않는다. 허용오차 1.0은 기능 시험용일 뿐 정확도 합격 기준이 아니다.

제품 정확도 평가는 실제 분포의 보정/평가 데이터와 허용 정확도 손실 기준을 정한 뒤 수행해야 한다. 이번 사전 분석에서 임의 정확도 기준이나 전체 데이터셋 정확도를 만들어 내지 않는다.

## 다음 진단과 진행 의사결정

[상세 진단 가이드](run-diagnostics-guide-ko.md)에 따라 사용자가 TIDL_RT_DEBUG=1, EP debug_level=1로 한 번 실행하고 전후 C71x trace·공유 로그·dmesg를 수집한다. 새 스크립트는 설치/remoteproc 조작/reader index 변경을 하지 않는다. 런타임 바이너리에 TIDL_RT_DEBUG 문자열이 있고 SDK lib_init에서 환경변수 해석을 확인했다. 공유 로그 구조는 app_utils/utils/console_io/include/app_log.h의 16개 x16KiB, 주소는 app_mem_map.h의 0xac000000/0x40000에 근거한다. live DT 예약을 확인한 뒤 읽기 전용 스냅샷을 만든다. 실제 보드 수집 스크립트 동작은 아직 미검증이다.

- **계속 진행:** 그래프 검증/버퍼 복사/처리 등 대기 구간과 수정 가능한 원인이 식별됨.
- **조건부 진행:** 기존 로그가 부족해 런타임/C71x에 추가 표식이 필요하고, 동일 버전 소스·컴파일러·메모리 검사·사용자 복구 조건을 확보할 수 있음. 필요한 구성요소만 격리 재빌드.
- **보류 권고:** 필수 소스/도구/관측·복구 수단을 확보할 수 없거나 필요한 변경이 Debian/현재 커널 계열 유지 조건과 충돌함. 이를 OS 자체의 불가능성으로 일반화하지 않음.

현재는 두 번째 판정이다. 먼저 기존 런타임 로그로 구간을 좁힌다. graph verify 이전이면 타깃 등록/descriptor·IPC를, verify 뒤 처리에서 멈추면 C71x 오류·버퍼 주소/캐시·MMA/메모리 자원을 조사한다. 입력/아티팩트 문제를 지시하는 오류가 나오면 그때 재컴파일하며 기존 세트는 보존한다. 성공 시 동일 입력의 수치 비교와 같은 실행의 C71x/MMA 프로파일을 확인하고, 마지막에 진단 제거·패치 재현성을 정리한다.

## 유지보수 비용과 미완료 항목

SDK 밖 커널 이식 4개 패치, noeth 빌드 구성, 격리된 TI ORT1.15 및 진단 라이브러리를 관리해야 한다. Debian 업데이트 후 커널 UAPI·모듈·부트 설정 회귀 검증이 필요하다. DMA 기능·RPMsg 수정과 보드 메모리 맵은 유지할 구현이며, 임시 로그는 최종 배포와 분리한다. 현재 성능·정확도·장시간 안정성·부팅 반복성·MMA 오프로딩은 완료로 주장하지 않는다.

## 참고 자료

- [TI J721E 11.02 SDK 구성과 대응 Linux/TIDL/MMALIB](https://software-dl.ti.com/jacinto7/esd/processor-sdk-rtos-jacinto7/11_02_00_06/exports/docs/psdk_rtos/docs/user_guide/sdk_components_j721e.html)
- [TI J721E TIDL 11.02 릴리스 노트](https://software-dl.ti.com/jacinto7/esd/processor-sdk-rtos-jacinto7/11_02_00_06/exports/docs/c7x-mma-tidl/TIDeepLearningProduct_ReleaseNotes.html)
- 로컬 SDK: c7x-mma-tidl/arm-tidl/rt/src/tidl_rt_ovx.c의 lib_init/verify_graph_tidl_tiovx/vxProcessGraph, app_utils 로그 구조와 vision_apps J721E app_mem_map.h.

## 후속 실기 결과 반영: 기능 포팅 경로 성립

fddW6r 단일 스레드 시험에서 실제 TIDL Run·CPU 출력 비교·benchmark·레이어 사이클 출력이 완료됐다. 초기의 Run 미완료 상태는 이 후속 결과로 대체된다. Debian 유지 경로에서 기능 추론이 가능한 근거를 확보했으므로 반복 재현성 검증을 진행한다. 정확한 스레딩 원인 분리는 미완료이며 제품 정확도·성능·장시간 안정성·MMA 직접 증거도 남는다. 작동 설정 기본화 및 [반복 검증 가이드](repeat-validation-ko.md)를 준비했다. 새 반복 바이너리의 보드 실행은 아직 수행하지 않았다.

## 반복 실행 실기 확인 — run-diag.HcuRol

프로젝트 루트 tidl-repeat-result.tar.gz를 docs/bbai64-survey/repeat-review/에 추출하고 수집 파일 45개의 checksum을 확인했다. Os1IYF 로그에서 warm-up 1회와 측정 10회 모두 TIDL_BENCHMARK_OK 및 서로 증가하는 subgraph 처리 구간을 확인했다. 종료 코드 0, worst_abs_error=0.722227, drift_from_first=0이다. 워밍업 제외 target.Run 평균 5.71518ms, 최소 5.32909ms, 최대 8.4768ms다. 디버그 출력·호스트 복사와 스케줄링을 포함한 단기 관측값이며 순수 MMA 성능·장시간 지표가 아니다.

**판정 갱신:** Debian 유지 조건에서 단일 ResNet18 모델의 반복 TIDL 기능 포팅 경로는 실기로 확인됐다. 기존 Run 정지는 현재 고정한 ORT 설정에서 재현되지 않았다. 스레딩 원인별 분리, 여러 입력의 정확도·장시간/재부팅 안정성, MMA 직접 지표는 남는다. 현재 커널·펌웨어 재빌드를 반복할 근거는 없다. 다음은 작동 세트의 해시/설정 고정과 재현 설치 절차 정리, SDK의 타깃 프로파일과 MMALIB 호출 근거 대조로 진행한다. 이미 성공한 기능 검증과 미완료 제품 검증을 구분한다.
