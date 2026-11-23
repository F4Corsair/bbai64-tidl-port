# J721E ONNX Model Compilation Environment

Vision Apps initialization in04 has passed at this stage. Next validate single-model offloading and CPU-reference output. Docker uses Ubuntu22.04 x86_64/Python 3.10/TIDL Tools 11_02_04_00/TI ORT 1.15.0/SOC J721E, including the official setup script at that tag. CPU host tools are used without a GPU.

## Prepare and run Docker

Run in the project's tidl directory. Docker Engine and the Compose plugin are required.

    docker compose build --progress plain
    docker compose run --rm compiler

The first build downloads TI binaries/example data. Inspect the first download error on failure. Inside the container:

    cd /opt/edgeai-tidl-tools
    source scripts/setup/setup_env.sh J721E
    cat /opt/tidl-source-commit.txt
    find "$TIDL_TOOLS_PATH" -maxdepth 2 -iname "*version*" -print
    python3 -c 'import onnxruntime as o; print(o.__version__, o.get_available_providers())'

Require ORT 1.15.0 and TIDLCompilationProvider, and a J721E Tools path. setup.sh is pinned to REL=11_02_04_00. Container /work persists in host tidl/work.

## Quantize and generate artifacts with the official example

Review configuration/preprocessing first.

    cd /opt/edgeai-tidl-tools/runtimes/examples/python/basic_example
    cat config.yaml
    python3 basic_example.py --help

Select an ONNX model in config.yaml. The05 probe supports one fixed-shape float32 input and one float32 output; start with a suitable classifier. Use the tagged config.yaml/--help for model keys/input settings. Enable only one model for the first test if multiple are configured.

    python3 basic_example.py --config ./config.yaml -r onnxrt --compile

This calibrates quantization with representative inputs and generates J721E network/subgraph artifacts. Calibration data should represent real usage. Record frame count, preprocessing, bit depth, and model selection. Treat the example's small frame count as a connectivity test, not an accuracy evaluation.

Copy the reported model/artifact paths under /work. If optimization changes ONNX, retain the file actually compiled. Preserve the full per-model artifact directory. Files only inside the disposable container disappear on exit; copy outputs/logs to /work.

## Meaning and generation of input.f32

input.f32 is the **numeric ONNX input tensor after preprocessing**, not a JPEG. It has no shape/dtype header.05 reads the model shape and expects exactly element-count×4 bytes. [1,3,224,224] float32 is602112 bytes.

Use the model's official preprocessing. RGB/BGR, resize/crop, NCHW/NHWC, and mean/scale vary by model. Quantized internal TIDL execution still accepts float32 when that is the external ONNX type.

Save the actual feed array immediately before passing it to ONNX; adapt the variable name to the example:

    numpy.save("/work/input.npy", input_tensor)

Then export against the same ONNX inside the container:

    python3 /workspace-scripts/export-input.py /work/model.onnx /work/input.npy /work/input.f32
    sha256sum /work/model.onnx /work/input.f32

export-input.py checks shape/type/byte count and writes input.f32.json. It assumes input.npy has already been correctly preprocessed. Record preprocessing separately in results.

## Transfer to the board and run05

Collect model.onnx, its artifact directory, input.f32, and metadata in host tidl/work. After the user copies them to the board:

    cd ~/bbai64-porting
    sudo bash scripts/05-check-onnx-ep.sh /absolute/path/model.onnx /absolute/path/artifacts /absolute/path/input.f32 ABS_TOLERANCE

Choose absolute tolerance from output scale/quantization requirements. Compare CPU/EP output and processing timing, then correlate C71x/MMA profiles from that same execution.

References: [pinned official guide](https://github.com/TexasInstruments/edgeai-tidl-tools/tree/11_02_04_00), [host setup code](https://github.com/TexasInstruments/edgeai-tidl-tools/blob/11_02_04_00/scripts/setup/setup.sh).
