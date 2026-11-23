| English | 한국어 |
|---|---|
| [English README](README.md) | [한국어 README](README-ko.md) |

# BBAI64 TIDL 포팅 기록

BeagleBone AI-64(J721E)에서 Debian을 유지하며 TI ONNX Runtime의 TIDL Execution Provider로 추론을 실행한 기록과 재현 자료입니다.

**확인된 성과:** ResNet18 전체 49개 노드 TIDL 배정, 실제 추론 및 CPU 출력 비교 통과, 워밍업 1회와 반복 10회 성공, 반복 출력 변화 0. MMA 직접 사용 근거·제품 정확도·장시간 안정성은 별도 검증 항목입니다.

## 먼저 읽을 문서

| 문서 | 내용 |
|---|---|
| [작업 재현 핵심 노트](summary/01-reproduction-ko.md) | 순정 상태에서 필요한 단계·버전·실행 명령·남은 작업 |
| [시행착오 확인용 노트](summary/02-troubleshooting-ko.md) | 단계별 문제와 해결, 상세 자료 링크 |
| [TIDL 포팅 정보 노트](summary/03-porting-checklist-ko.md) | 다른 버전·보드에서 확인할 호환성 및 검증 기준 |

필수 패치·설정·스크립트는 [summary/files](summary/files)에 있습니다. SDK·Linux 전체 소스·대용량 빌드 결과·모델은 포함하지 않습니다. 단축 재현 절차 전체를 새 순정 SD에서 다시 시험한 것은 아니므로 핵심 노트의 전제와 중단 조건을 확인하세요.

## 검증 구성

| 항목 | 버전·설정 |
|---|---|
| 보드 | BeagleBone AI-64 / TI J721E |
| OS | Debian 13.6 |
| 커널 | 6.18.39-arm64-k3-r47 기반, 호환 패치 적용 tidl3 |
| PSDK | RTOS 11.02.00.06 / 대응 Linux 11.02.00.04 |
| TIDL Tools / TI ONNX Runtime | 11_02_04_00 / 1.15.0 |
| MCU2_0 펌웨어 | ETHFW 비활성화 |
| ORT 실행 | 단일 스레드·순차 실행·spin 비활성화 |

## 상세 근거

- [포팅 가능성·양자화 재평가 및 반복 검증 결과](bbai64-porting/docs/porting-reassessment-ko.md)
- [IPC·RPMsg·TIDL 실행 장애 분석](bbai64-porting/docs/rpmsg-failure-analysis-ko.md)
- [ETHFW의 역할과 비활성화 영향](bbai64-porting/docs/ethfw-role-and-disable-ko.md)
- [초기 SDK·Device Tree 사전 분석](docs/psdk-porting-preanalysis-ko.md)

상세 문서는 조사 당시의 상태와 중간 절차를 포함합니다. 재현은 최신 핵심 노트를 우선하고, 과거 실패 단계를 그대로 반복하지 마세요.

## 작업 원칙

SDK 원본은 읽기 전용으로 유지합니다. 커널 빌드와 배포, 보드 업로드·설치·재부팅은 사용자가 수행합니다. 정상 부트 환경과 SD 복구 수단을 보존한 상태에서 단계별로 적용합니다.

이 저장소는 README, summary 전체 및 summary에서 참조하는 Markdown 문서를 중심으로 관리합니다. 제외된 바이너리·로그 링크는 원래 작업 공간이 있어야 열릴 수 있습니다.

## 개발 노트

이 프로젝트는 AI 코딩 도구의 도움을 받아 개발되었습니다. 포팅 절차, 커널 수정 사항 및 검증 결과는 프로젝트의 개발·시험 기록을 바탕으로 문서화했습니다.

이 저장소는 독립적인 실험 프로젝트이며, Texas Instruments 또는 BeagleBoard.org의 공식 지원을 받지 않습니다.
