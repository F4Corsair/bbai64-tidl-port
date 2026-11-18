# Step 05 ResNet18 실행 자료

공식 ResNet18 opset9를 J721E TIDL Tools 11_02_04_00과 TI ORT 1.15.0에서 컴파일했다.
공식 8-bit 보정 설정(calibration_frames=2, iterations=5)을 사용했다. 연결 검증용 설정이며 정확도 평가는 별도로 수행한다.

input.f32는 공식 airshow.jpg를 공식 DatasetLoader와 PreProcess로 처리한 [1,3,224,224] little-endian float32 배열이다. 크기는 602112바이트다. RGB 이미지 로더 및 config의 채널별 mean/scale을 사용했다.

x86 TIDL 추론은 성공했으며 CPU와 최대 절대오차는 0.72222900390625, 두 결과의 top1은 895로 일치했다. 아래의 허용오차 1.0은 이 한 입력의 호스트 결과를 바탕으로 제안한 연결 시험용 기준이다. 모델 전체의 정확도 기준으로 검증된 값은 아니다.

이 디렉터리 전체를 보드의 ~/bbai64-porting/test-data/resnet18에 복사한 뒤 실행한다.

    cd ~/bbai64-porting/test-data/resnet18
    sha256sum -c SHA256SUMS
    cd ~/bbai64-porting
    sudo bash scripts/05-check-onnx-ep.sh \
      "$HOME/bbai64-porting/test-data/resnet18/model.onnx" \
      "$HOME/bbai64-porting/test-data/resnet18/artifacts" \
      "$HOME/bbai64-porting/test-data/resnet18/input.f32" 1.0

아티팩트 경로는 onnxrtMetaData.txt와 subgraph_0_tidl_net.bin이 있는 artifacts 디렉터리다.
보드에서 실제 C71x/MMA 실행 및 결과는 아직 미검증이다.
