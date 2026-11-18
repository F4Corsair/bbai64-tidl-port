# J721E ONNX 모델 컴파일 환경

Step 04의 Vision Apps 초기화까지 통과했다. 다음 목표는 단일 ONNX 모델의 오프로딩과 CPU 대비 출력 검증이다. 이 Docker 환경은 Ubuntu 22.04 x86_64 / Python 3.10 / TIDL Tools 11_02_04_00 / TI ORT 1.15.0 / SOC J721E를 사용한다. 공식 setup 스크립트도 해당 태그에 고정했다. GPU 없이 CPU 호스트 도구를 사용한다.

## Docker 준비와 실행

프로젝트의 tidl 폴더에서 실행한다. 호스트에 Docker Engine과 Compose 플러그인이 필요하다.

    docker compose build --progress plain
    docker compose run --rm compiler

처음 빌드는 TI 바이너리와 공식 예제 데이터를 다운로드한다. 실패 시 첫 다운로드 오류를 확인한다. 컨테이너에 들어가 다음을 실행한다.

    cd /opt/edgeai-tidl-tools
    source scripts/setup/setup_env.sh J721E
    cat /opt/tidl-source-commit.txt
    find "$TIDL_TOOLS_PATH" -maxdepth 2 -iname "*version*" -print
    python3 -c 'import onnxruntime as o; print(o.__version__, o.get_available_providers())'

ORT 1.15.0과 TIDLCompilationProvider를 확인한다. Tools 경로가 J721E인지 확인한다. 태그 버전은 setup.sh의 REL=11_02_04_00으로 고정했다. 컨테이너 /work는 호스트 tidl/work에 저장된다.

## 공식 예제로 양자화 및 아티팩트 생성

먼저 공식 예제 설정과 전처리를 검토한다.

    cd /opt/edgeai-tidl-tools/runtimes/examples/python/basic_example
    cat config.yaml
    python3 basic_example.py --help

config.yaml에서 ONNX 모델을 선택한다. Step 05 실행기는 고정 shape float32 입력 1개, float32 출력 1개를 지원하므로 첫 모델은 해당 조건을 만족하는 분류 모델로 선택한다. 모델 선택 키와 입력 데이터 설정은 태그에 포함된 config.yaml 및 --help를 기준으로 설정한다. 여러 모델이 설정돼 있으면 첫 시험에 쓸 하나만 활성화한다.

    python3 basic_example.py --config ./config.yaml -r onnxrt --compile

이 과정에서 대표 입력을 이용해 양자화 보정을 수행하고 J721E용 네트워크와 서브그래프 아티팩트를 만든다. 보정 입력은 실제 사용 데이터의 분포를 대표해야 한다. 보정 프레임 수, 전처리, bit depth와 모델 선택을 기록한다. 기본 예제의 적은 프레임 수는 연결 시험용으로 보고 정확도 평가 시 별도 검토한다.

공식 예제가 안내한 모델·아티팩트 경로를 /work 아래로 복사한다. 모델 최적화가 수행됐다면 컴파일에 실제 사용한 ONNX를 사용한다. 아티팩트는 모델별 디렉터리 전체를 보존한다. 컨테이너 내부에만 있는 파일은 종료하면 사라지므로 결과와 로그를 /work로 복사한다.

## input.f32의 의미와 생성

input.f32는 전처리가 끝난 **ONNX 입력 텐서의 숫자 배열**이다. JPEG 파일을 그대로 전달할 수 없으며 shape나 dtype을 저장하는 헤더도 없다. Step 05는 모델의 shape를 읽어 원소 수 × 4바이트를 정확히 읽는다. 예를 들어 [1,3,224,224] float32는 602112바이트다.

입력 생성에는 선택한 모델의 공식 전처리를 그대로 사용한다. 이미지의 RGB/BGR, resize/crop, NCHW/NHWC, mean·scale 적용 여부는 모델별로 다르다. 양자화된 TIDL 내부 실행에도 외부 ONNX 입력 타입이 float32라면 float32 입력을 준다.

공식 예제 또는 전처리 코드에서 ONNX 세션에 전달하기 직전의 feed 배열 하나를 다음처럼 저장한다. 배열 이름은 해당 예제의 실제 feed 변수에 맞춘다.

    numpy.save("/work/input.npy", input_tensor)

컨테이너에서 같은 ONNX와 대조해 raw 파일로 내보낸다.

    python3 /workspace-scripts/export-input.py /work/model.onnx /work/input.npy /work/input.f32
    sha256sum /work/model.onnx /work/input.f32

export-input.py는 모델 shape·타입·바이트 수를 검증하고 input.f32.json도 만든다. 이 도구의 전제는 이미 공식 전처리를 적용한 input.npy다. 전처리 방식은 결과 보고에 별도로 기록한다.

## 보드 전달 및 Step 05

호스트 tidl/work에 model.onnx, 모델 아티팩트 디렉터리, input.f32와 메타데이터를 모은다. 사용자가 이를 보드에 복사한 뒤 실행한다.

    cd ~/bbai64-porting
    sudo bash scripts/05-check-onnx-ep.sh /절대경로/model.onnx /절대경로/artifacts /절대경로/input.f32 허용절대오차

허용오차는 해당 모델의 출력 스케일과 양자화 오차 기준으로 정한다. CPU와 EP 출력 비교 및 TIDL 처리 시간 확인 후 같은 실행의 C71x/MMA 프로파일을 대조한다.

참고 자료는 [태그 고정 공식 가이드](https://github.com/TexasInstruments/edgeai-tidl-tools/tree/11_02_04_00)와 [호스트 setup 코드](https://github.com/TexasInstruments/edgeai-tidl-tools/blob/11_02_04_00/scripts/setup/setup.sh)다.
