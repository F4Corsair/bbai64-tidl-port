# ResNet18 컴파일 SIGBUS 조사

## 조사 결과

**Docker의 64 MiB 공유 메모리 한도 소진이 직접적인 원인으로 판단된다.** 같은 이미지와 공식 ResNet18 설정에서 실패를 재현했다. 공유 메모리 확장 후의 성공 여부는 아직 시험하지 않았다.

| 항목 | 관측 결과 |
|---|---|
| 이미지 | bbai64-tidl:11_02_04_00-j721e |
| 실행 | 공식 basic_example, onnxrt, cl-ort-resnet18-v1, --compile |
| 설정 | SOC=J721E, CPU Tools, 8-bit, calibration_frames=2, iterations=5 |
| 초기 /dev/shm | 64 MiB, 사용량 0 |
| 실패 위치 | tivxInit Initialization Done 직후 |
| 종료 | SIGBUS, 프로세스 종료 코드 135 |
| 종료 직후 /dev/shm | 64 MiB 사용, 100%, 잔여 0 |
| 공유 파일 | vashm_buff_*_0 약 370 KiB, vashm_buff_*_1 약 80 MiB |

[재현 로그](logs/resnet18-sigbus.log)와 [컨테이너 설정·공식 옵션 조회](logs/container-inspection.log)를 보존했다. 재현 컨테이너는 --rm으로 종료됐다. 영속 작업 폴더의 모델·입력을 변경하는 명령은 실행하지 않았다.

## 원인 해석

현재 compose.yaml에는 shm_size가 지정되지 않았다. 컨테이너에서 실제 측정한 /dev/shm은 64 MiB다. 호스트 에뮬레이션 allocator는 공유 파일을 생성하고 ftruncate로 크기를 설정한 뒤 mmap으로 접근한다. 파일의 논리 크기가 tmpfs 여유보다 커도 생성·크기 설정은 성공할 수 있으며, 실제 페이지에 접근하는 과정에서 저장 공간이 소진되면 SIGBUS가 발생할 수 있다. 이번에는 80 MiB 공유 파일과 64 MiB tmpfs 소진이 같은 실행에서 확인됐다. SDK의 관련 코드 위치는 app_utils/utils/mem/src/app_mem_pc.c의 mmap(296행) 및 ftruncate(679행)다.

기존 Docker 준비 과정에서 실제 모델 컴파일의 공유 메모리 요구량을 검증하지 못했고 compose에 용량을 지정하지 않은 점이 이번 문제를 만들었다. ORT와 Tools 버전 검사는 통과했지만 모델 컴파일 시험까지 필요했다.

## 검토할 해결안과 통과 기준

권장 변경은 compose의 compiler 서비스에 shm_size: "1gb"를 추가하는 것이다. 이는 이 모델의 최소 요구량을 의미하지 않으며 첫 진단 재실행을 위한 여유 한도다. 실제 사용 페이지에 따라 호스트 메모리가 소비된다. 이미지 재빌드는 필요하지 않고 새 컨테이너를 만들어야 한다.

사용자 검토 후 같은 모델·버전·보정 설정을 유지하고 /dev/shm만 1 GiB로 바꿔 한 번 재실행한다. 성공 기준은 종료 코드 0, 모델 아티팩트 생성, SIGBUS 부재다. 실패하면 종료 코드와 첫 오류, 공유 메모리 사용량을 다시 수집해 다음 원인을 조사한다.

검토 전에는 compose 용량 변경 및 확장 환경에서의 컴파일을 수행하지 않았다.

## 수정 적용 결과

compose의 shm_size를 1 GiB로 변경한 뒤 동일 공식 모델의 컴파일이 종료 코드 0으로 완료됐다. 호스트 TIDL 추론도 통과했다. 모델·아티팩트·전처리 입력·CPU 및 호스트 TIDL 출력은 tidl/ready/resnet18에 준비했다. 호스트 최대 절대오차와 보드 시험 기준은 해당 디렉터리의 README에 기록했다.
