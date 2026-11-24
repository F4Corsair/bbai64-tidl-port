# BBAI64 TI Python ORT 검증 가이드

이 실험은 기존 ResNet18 모델과 TIDL 아티팩트에 대해 Python ORT 스레드 설정만 바꾼다. B가 통과하면 TI 공식 Wrapper의 스레드 설정을 지원한다. 이어 같은 릴리스의 Wrapper 자체를 시험한다. C는 참고 결과로 기록한다.

| 케이스 | 설정 |
|---|---|
| A | intra/inter-op 1, 순차 실행, 양쪽 spinning 비활성화 |
| B | intra-op 1, 나머지 스레드 옵션 기본값 |
| C | 모든 스레드 옵션 기본값 |
| wrapper | TI TIDL Tools 11_02_04_00의 Python Wrapper |

## 호스트 준비

프로젝트 루트에서 실행한다. 이미 준비된 묶음이 있으면 `prepare.sh` 호출을 생략하고 SHA256만 확인한다.

```bash
exp="$PWD/bbai64-porting/python-ort-validation"
bash "$exp/prepare.sh" "$exp/python-ort-bbai64.tar.gz"
sha256sum "$exp/python-ort-bbai64.tar.gz"
```

묶음은 로컬 원본 SDK 이미지에서 Python 3.12, 표준 라이브러리 및 SDK 패키지를 추출하고, 커밋이 고정된 TI Wrapper를 포함한다. 시스템 설치 없이 사용한다. 현재 보드의 기본 Python은 3.13.5다.

## 보드 실행 및 로그 회수

기존 진단과 같은 장치 권한이 필요하다. 보드 기본 계정은 DMA heap 및 RPMsg 제어 장치의 읽기·쓰기 권한이 없어, 사용자가 직접 아래 절차를 실행한다. 호스트의 SSH 별칭은 기존 `beagle`을 사용한다.

```bash
remote_dir=$(ssh beagle 'mktemp -d /tmp/bbai64-python-ort.XXXXXXXX')
scp "$exp/python-ort-bbai64.tar.gz" "beagle:$remote_dir/"
ssh -t beagle "cd '$remote_dir' &&
    tar -xzf python-ort-bbai64.tar.gz &&
    bash run.sh \"\$HOME/models/resnet18\""
```

실행기는 묶음 해시, Python/ORT 버전과 EP 가용성을 확인한 뒤 `sudo`로 각 케이스를 독립 실행한다. 각 실행은 120초 제한과 5초 강제 종료 유예를 적용한다. 기본 경로의 모델 및 아티팩트 위치가 다르면 첫 인자를 실제 디렉터리로 지정한다. 보드의 커널, DT, 펌웨어, 기존 라이브러리와 모델은 그대로 둔다.

아래 `result_name`에는 보드 출력에 표시된 실제 `results.*` 디렉터리 이름을 넣는다. 이전 로그와 섞이지 않게 새 호스트 디렉터리를 사용한다.

```bash
result_name=results.XXXXXXXX
local_run=$(mktemp -d "$exp/board-results.XXXXXXXX")
ssh beagle "cd '$remote_dir/$result_name' &&
    find . -type f -not -path '*/artifacts/*' -print0 |
    tar --null -T - -cf -" > "$local_run/results.tar"
tar -xf "$local_run/results.tar" -C "$local_run"
find "$local_run" -name '*.log' -o -name cases.tsv
(cd "$local_run" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
```

로컬에서 `cases.tsv`와 실패 케이스 로그를 확인한 뒤, 보드에서 해당 세션의 임시 디렉터리만 정리한다. `remote_dir`를 실제 값을 확인한 상태에서 사용한다.

```bash
ssh -t beagle "case '$remote_dir' in /tmp/bbai64-python-ort.*) sudo rm -rf -- '$remote_dir';; *) exit 2;; esac"
```

Python import 단계에서 실패하면 보드 터미널 출력과 생성된 `runner.log`를 보존한다. 장치 접근 실패, C71x 상태 변화, 기준선 재시험 실패가 나오면 반복 실행 전에 로그를 회수한다.

## 결과 확인

- 각 케이스는 워밍업 1회와 같은 세션에서 반복 10회를 수행한다. 각 호출의 CPU/TIDL 출력은 유한한 동일 형상·자료형이어야 하고 CPU 대비 최대 절대오차는 1.0 이하여야 한다. 양의 TIDL subgraph 처리 구간을 매회 확인한다.
- `cases.tsv`에서 종료 코드와 마지막 Python 단계, EP Invoke와 graph 로그 수를 확인한다. Invoke 수에는 진입과 완료 메시지가 모두 포함된다. 정확한 표식과 오류는 각 `probe.log`에 있다. 표식 누락은 해당 단계의 미관측으로 기록한다.
- `comparison.log`는 이번 A의 첫 원시 출력과 해당 케이스의 11개 출력 사이의 최대 절대차를 보여준다. 과거 보드 비교 기준은 CPU 대비 최대오차 0.722227, 반복 편차 0이다. 과거 로그에는 원시 배열이 없어 새 A의 배열을 직접 비교 기준으로 사용한다.
- A가 실패하면 중단한다. B 또는 C 실패 후에는 A를 다시 실행해 기본 상태를 확인한다. A가 통과하고 B가 실패하면 스레드 옵션을 하나씩 추가하고, 단일 옵션이 모두 실패하면 두 옵션 조합을 시험한 뒤 최소 통과 후보를 재실행한다. B가 성공하면 Wrapper 자체를 시험한다.
