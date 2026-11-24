# TI Python ORT 검증 결과

## 확인됨

- 기존 보드 C++ 기준선에서 워밍업 1회와 반복 10회가 통과했다. CPU 대비 최대 절대오차는 0.722227이고 반복 편차는 0이다. [기존 결과](../docs/porting-reassessment-ko.md)
- 보드 일반 계정에서 기본 Python 3.13.5와 NumPy·ORT 미설치를 확인했다. DMA heap과 C71x RPMsg 제어 장치는 일반 계정에 읽기·쓰기 권한이 없다.
- SDK 이미지에 AArch64 Python 3.12, NumPy, TI Python ORT 바인딩이 있다. TI 공식 Python Wrapper는 intra-op을 1로 고정한다. [공식 소스](https://github.com/TexasInstruments/edgeai-tidl-tools/blob/bb029fb79929e0fc0c2c13d2d40b13237eabbca1/runtimes/tidl_wrapper/python/onnxrt/onnxrt_wrapper.py#L196-L226)
- 보드의 일반 계정으로 묶음의 내부 해시를 검증하고 Python 3.12.12, NumPy 1.26.4, TI ORT 1.15.0 import와 `TIDLExecutionProvider` 등록을 확인했다. 임시 디렉터리 삭제도 확인했다. [보드 사전 점검 로그](board-import-preflight.log)

## 보드 검증 결과

`results.DjdXAu`에서는 보드의 Python import와 TIDL EP 등록을 통과했다. C71x 상태는 `running`, 펌웨어는 `j7-c71_0-fw`였다. 실행기가 두 sysfs 파일을 줄바꿈으로 연결하고 한 줄과 비교해 Case A 전에 중단했다. 회수된 아카이브에는 `runner.log`와 `environment.log`만 있다. 상태와 펌웨어를 한 줄로 출력하도록 실행기를 수정했다. [실기 로그](board-results.3iiZJLRM/runner.log)

`results.LISG0J`에서는 Debian 13, 커널 `6.18.39-arm64-k3-r47-tidl3`, C71x 펌웨어 `j7-c71_0-fw`, Python 3.12.12, TI ORT 1.15.0으로 ResNet18을 실행했다. 회수 파일의 SHA256을 검증했고, 모델과 입력의 해시가 준비 자료와 일치했다. [실행 요약](board-results.yuaCA2OL/cases.tsv), [환경 및 입력 해시](board-results.yuaCA2OL/environment.log)

| 케이스 | 종료 코드 | 통과한 추론 | CPU 대비 최대 절대오차 | A 대비 최대 절대차 |
|---|---:|---:|---:|---:|
| A · 기존 우회 설정 | 0 | 11/11 | 0.7222270966 | 0 |
| B · `intra-op=1`만 지정 | 0 | 11/11 | 0.7222270966 | 0 |
| C · ORT 스레드 기본값 | 0 | 11/11 | 0.7222270966 | 0 |
| TI 공식 Python Wrapper | 0 | 11/11 | 0.7222270966 | 0 |

각 케이스에서 워밍업 1회와 반복 10회 모두 EP 호출 완료와 양의 TIDL subgraph 처리 구간을 확인했다. 반복 출력 편차는 모두 0이며 네 출력 배열 파일의 SHA256도 동일하다. 최대 절대오차는 과거 보드 결과 `0.722227`과 보고 정밀도에서 일치한다. [A 로그](board-results.yuaCA2OL/A/probe.log), [B 로그](board-results.yuaCA2OL/B/probe.log), [C 로그](board-results.yuaCA2OL/C/probe.log), [공식 Wrapper 로그](board-results.yuaCA2OL/wrapper/probe.log)

**판정.** 이번 보드 구성과 ResNet18 입력에서 TI 공식 Python Wrapper를 사용할 수 있다. B가 통과해 기존의 추가 inter-op, 순차 실행, spinning 설정은 필요하지 않았다. C도 통과했으므로 직접 Python 세션을 만들 때 명시해야 할 스레드 옵션은 이번 시험에서 없었다. B가 성공해 추가 ablation은 생략했다. 과거 C++ 시간 초과의 원인과 다른 모델에서의 동작은 미확인이다.
