# BBAI64 TIDL EP 포팅 계획

**검토용 패키지 · 실기 미검증.** Debian 13.6 / 6.18.39-arm64-k3-r47 및 BBAI64 부트 체인을 기준으로 한다. SDK RTOS 11.02.00.06 / Linux 11.02.00.04 / Tools 11_02_04_00 / TI ORT 1.15.0을 고정한다. [TI 버전 표](https://github.com/TexasInstruments/edgeai-tidl-tools/tree/11_02_04_00#version-compatibility)

- [수동 배치 및 검증](deployment-guide-ko.md), [미해결 항목](unresolved-issues-ko.md), [결과 양식](validation-results-template-ko.md)
- [원본·경로·해시·링크·SONAME·NEEDED](../staging/manifests/components.tsv), [펌웨어 매핑](../staging/manifests/firmware-map.tsv), [정적 검사 로그](offline-validation.log)
- `staging/dt/`에 실기 부트 DTB를 기반으로 생성한 후보와 TI 참조 자료를 제공한다. `scripts/prepare-dt.py`로 재생성 가능하다. EVM DTBO는 주소 및 정책 비교 자료다.
- `staging/firmware/`에 C71x, C66x 2개, MAIN R5F 2개와 서명 변형을 준비했다. 기존 MCU R5F는 그대로 유지한다. MAIN R5F1 쌍은 참조가 충돌하지 않도록 SDK 맵에 맞추었으며 해당 펌웨어는 배치하지 않는다.
- `staging/lib/`는 TI ORT와 provider, TIDL-RT, Vision Apps(TIOVX 포함), rpmsg-char의 격리 세트다. EGL/GLES/GBM 및 C/C++ 런타임은 Debian 제공 SONAME을 사용한다.
- 시험은 기준선 → 후보 DT 및 커널 계약 → 코어 → RPMsg/DMA → TIOVX → ONNX 출력 및 오프로딩 증거 순으로 수행한다. 커널 패치, 모델 컴파일과 실기 가속 검증은 남아 있다.

정적 검사에서 DDR ELF 세그먼트와 리소스 테이블이 해당 carveout에 포함됐고, 활성 예약 구간 26개가 서로 겹치지 않았다. 관측된 CMA와 OP-TEE를 함께 검사했다. 기존 주변장치 및 MCU 노드의 속성과 FDT 예약 테이블을 보존했다. C71x high heap·R5F TCM 변환·커널 보안 정책·ETHFW 자원은 실기 검증 대상이다. 후보 DTB는 Python FDT 도구로 생성했고 DTC 빌드나 보드 부팅은 수행하지 않았다.

## UART 및 TI Git 없이 진행하는 경우

플래시 직후 보존할 데이터가 없다면 전체 백업을 생략할 수 있다. SSH 장애 시 SD를 다른 PC에서 복구하거나 재플래시할 수 있는지 먼저 확인한다. 시험 엔트리의 고유 cmdline 마커와 live DT 검사를 함께 사용하면 재부팅 후 SSH에서 적용 여부를 확인할 수 있다.

커널 소스 확보는 부트 및 remoteproc 확인의 선행 조건에서 제외했다. 펌웨어를 추가하기 전에 DT만 시험 부팅하고, 이후 코어·RPMsg를 확인한다. DMA heap과 주소 조회는 추론 진행 여부를 결정하는 별도 기능 검사다. [수동 배치 가이드](deployment-guide-ko.md)
