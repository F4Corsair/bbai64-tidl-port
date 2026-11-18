# 다른 버전·보드에서 TIDL 포팅 시 확인할 정보

## 1. 버전 세트를 먼저 고정

TIDL Tools/모델 importer, ARM runtime/EP/ORT, C71x TIDL/MMALIB, Vision Apps/TIOVX/app_utils, RTOS·PDK·SYSFW, Linux UAPI를 각각 기록한다. 마케팅상 11.02가 같다는 이유만으로 교환하지 않는다. 도구 태그·커밋·바이너리 해시·SONAME·의존 심볼·실제 로딩 경로가 근거다. 공식 J721E 11.02 RTOS 문서는 Linux11.02.00.04/TIDL11_02_04_00/MMALIB11_02_00_06을 명시한다. [공식 구성](https://software-dl.ti.com/jacinto7/esd/processor-sdk-rtos-jacinto7/11_02_00_06/exports/docs/psdk_rtos/docs/user_guide/sdk_components_j721e.html)

## 2. 보드/부트/메모리 계약

- SoC·보안 GP/HS·서명 요구·부트 저장장치·실제 extlinux 항목·initrd 포함 펌웨어 확인.
- 보드 DTS include/overlay를 보존하고 reserved-memory와 ELF LOAD/resource table/trace/vring/공유 descriptor를 대조.
- memory-region 순서와 phandle을 실제 커널 드라이버로 검증. C66 DMA 풀 이름만 보고 의도 추정 금지.
- DMA 주소=물리주소 가정, IOMMU·연속성·주소폭·cache sync·CMA/전용 heap을 확인. 일반 heap 이름 변경은 호환 패치가 아님.
- SYSFW 자원 배분·IRQ/UDMA·MMA 관련 설정은 Sciclient 일부 성공만으로 전체 호환이라 판단하지 않음.

## 3. 호스트/커널/RTOS 경계

커널 기능 설정과 실제 동작을 함께 검사한다. 이 프로젝트의 TI ioctl/exporter 패치를 다른 커널에 그대로 적용하지 말고 ABI·장치 lifetime·DMA parent·보안 제한을 재검토한다. RPMsg 자동 할당 요청값 ANY와 실제 주소를 구분한다. 주소를 상수로 바꾸지 말고 커널 할당/반환을 맞춘다. SDK/OS ORT를 격리하고 Debian GLIBC가 더 최신이라는 사실만으로 전체 ABI 호환을 보장하지 않는다.

EVM 펌웨어는 GESI/QENET·DSS/I2C·pinmux 등에 의존할 수 있다. ETHFW 제외는 이번 BBAI64의 선택이며 모든 보드의 필수 설정이 아니다. Ethernet 가상 포트·gPTP/TSN 관련 기능을 요구하면 별도 보드 지원이 필요하다. R5F/C71x trace와 일반 공유 로그는 다르며 캐시 가시성 및 과거 로그를 구분한다.

## 4. 모델/양자화 계약

SoC와 Tools를 고정하고 모델·아티팩트·입력·전처리를 해시로 한 세트 관리한다. RGB/BGR, NCHW/NHWC, shape/dtype, mean/scale, byte order를 확인한다. 호스트 CPU/TIDL 성공은 전처리/파일 오류를 줄여 주지만 C71x 코드 생성·자원 문제까지 배제하지 않는다. calibration2/iterations5·한 이미지 top1 일치는 제품 정확도 검증이 아니다. 대표 보정/평가 데이터와 수용할 정확도 손실은 용도별로 정한다.

## 5. 성공 수준과 중단 기준

1. 장치 열거 → 초기화 → 실제 graph verify/remote create → Run/출력 반환 순서로 구분한다.
2. CPU 대비 오차·유한값·shape·반복 drift·각 실행의 benchmark 구간을 확인한다.
3. C71x 경로와 MMA 직접 프로파일을 분리한다. 레이어 사이클만으로 특정 MMA 명령을 직접 증명했다고 하지 않는다.
4. debug 포함 host Run 시간과 순수 가속 시간·제품 성능을 혼합하지 않는다.
5. timeout은 마지막 표식·스택/시스템 호출로 좁히고, 근거 없이 연장/재컴파일하지 않는다.

**확인됨/가능성 높음/미확인**으로 판단을 기록한다. 계속 진행은 수정 가능한 구간이 특정될 때, 조건부 진행은 필요한 소스·도구·복구 수단을 확보할 수 있을 때, 보류는 그 필수조건을 확보할 수 없을 때다. Debian 유지가 불가능하다는 결론은 구체적인 막힌 인터페이스가 근거여야 한다.

## summary/files의 범위

포함: 커널4패치·빌드설정/스크립트, noeth 재빌드 패치/도구, 기준/후보DT·맵, 검증 스크립트·ORT 헤더/실행기 소스, 소형 RPMsg0.6.11 진단 라이브러리, SDK 원본 경로/해시 매니페스트와 선택 추출기. 라이브러리의 사용 조건은 원 TI SDK 라이선스를 따른다. RPMsg 라이브러리의 진단 패치와 TI 라이선스는 files/rpmsg-work에 동봉했다.

제외: Linux/SDK 전체 소스, 커널 image/전체모듈, SDK runtime 대형 바이너리, RTOS ELF, 모델/아티팩트, Docker 이미지와 과거 trace 전체. 원 프로젝트와 고정 SDK에서 선택 생성한다. 큰 파일이 필요 없는 것은 아니며 summary 중복 보관을 생략한 것이다. 이 세 문서는 원 프로젝트를 참조하는 인덱스이므로 보조 링크까지 쓰려면 원 프로젝트도 보존한다.
