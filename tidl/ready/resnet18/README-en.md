# ResNet18 Test Data for Step 05

Official ResNet18 opset9 was compiled with J721E TIDL Tools 11_02_04_00 and TI ORT 1.15.0 using the official8-bit calibration settings (calibration_frames=2, iterations=5). These are connectivity-test settings; accuracy evaluation is separate.

input.f32 is a little-endian float32 [1,3,224,224] array generated from official airshow.jpg through official DatasetLoader/PreProcess. Size602112 bytes. It uses the RGB loader and per-channel mean/scale from config.

x86 TIDL inference passed. Maximum CPU-reference absolute error was0.72222900390625; both top1 indices were895. Tolerance1.0 below is a connectivity-test suggestion based on this one host input, not a validated overall accuracy threshold.

Copy this entire directory to ~/bbai64-porting/test-data/resnet18 on the board, then run:

    cd ~/bbai64-porting/test-data/resnet18
    sha256sum -c SHA256SUMS
    cd ~/bbai64-porting
    sudo bash scripts/05-check-onnx-ep.sh \
      "$HOME/bbai64-porting/test-data/resnet18/model.onnx" \
      "$HOME/bbai64-porting/test-data/resnet18/artifacts" \
      "$HOME/bbai64-porting/test-data/resnet18/input.f32" 1.0

The artifact path is the directory containing onnxrtMetaData.txt and subgraph_0_tidl_net.bin. Actual board C71x/MMA execution and output remained Unverified when this note was prepared.
