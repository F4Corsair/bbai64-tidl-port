#include "onnxruntime_cxx_api.h"
#include "tidl_provider_factory.h"

#include <algorithm>
#include <cmath>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <vector>

int main(int argc, char **argv)
{
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::setvbuf(stderr, nullptr, _IONBF, 0);
    const auto started = std::chrono::steady_clock::now();
    auto stage = [&](const char *s) {
        std::cerr << "PROBE_STAGE ms=" << std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - started).count() << " " << s << std::endl;
    };
    try {
        if (argc != 5) throw std::runtime_error("usage: ort-probe model.onnx artifacts input.f32 tolerance");
        const float tolerance = std::stof(argv[4]);
        if (!std::isfinite(tolerance) || tolerance < 0) throw std::runtime_error("invalid tolerance");
        if (!std::filesystem::is_directory(argv[2])) throw std::runtime_error("missing artifacts");
        Ort::Env env(ORT_LOGGING_LEVEL_WARNING, "bbai64-test");
        Ort::SessionOptions cpu, accelerated;
        {
            const char *single = std::getenv("BBAI64_ORT_SINGLE_THREAD");
            if (!single) single = "1";
            if (std::strcmp(single, "1") != 0 && std::strcmp(single, "0") != 0)
                throw std::runtime_error("BBAI64_ORT_SINGLE_THREAD must be 0 or 1");
            if (std::strcmp(single, "1") == 0) {
                for (auto *opt : {&cpu, &accelerated}) {
                    opt->SetIntraOpNumThreads(1);
                    opt->SetInterOpNumThreads(1);
                    opt->SetExecutionMode(ExecutionMode::ORT_SEQUENTIAL);
                    opt->AddConfigEntry("session.intra_op.allow_spinning", "0");
                    opt->AddConfigEntry("session.inter_op.allow_spinning", "0");
                }
                stage("ORT threads=1 execution=sequential spinning=off");
            }
        }
        c_api_tidl_options options{};
        Ort::ThrowOnError(OrtSessionsOptionsSetDefault_Tidl(&options));
        if (const char *level = std::getenv("BBAI64_TIDL_DEBUG")) {
            if (std::strcmp(level, "1") != 0 && std::strcmp(level, "0") != 0)
                throw std::runtime_error("BBAI64_TIDL_DEBUG must be 0 or 1");
            options.debug_level = std::atoi(level);
        }
        if (std::strlen(argv[2]) >= sizeof(options.artifacts_folder)) throw std::runtime_error("artifact path too long");
        std::strcpy(options.artifacts_folder, argv[2]);
        Ort::ThrowOnError(OrtSessionOptionsAppendExecutionProvider_Tidl(accelerated, &options));
        stage("before cpu_session");
        Ort::Session reference(env, argv[1], cpu);
        stage("after cpu_session");
        stage("before tidl_session");
        Ort::Session target(env, argv[1], accelerated);
        stage("after tidl_session");
        if (reference.GetInputCount() != 1 || reference.GetOutputCount() != 1)
            throw std::runtime_error("requires one input and one output");
        Ort::AllocatorWithDefaultOptions allocator;
        auto input_name = reference.GetInputNameAllocated(0, allocator);
        auto output_name = reference.GetOutputNameAllocated(0, allocator);
        const char *in_name = input_name.get(), *out_name = output_name.get();
        auto input_type = reference.GetInputTypeInfo(0);
        auto info = input_type.GetTensorTypeAndShapeInfo();
        auto shape = info.GetShape();
        if (info.GetElementType() != ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT ||
            std::any_of(shape.begin(), shape.end(), [](int64_t x) { return x <= 0; }))
            throw std::runtime_error("requires static float32 input");
        size_t count = 1;
        for (int64_t dim : shape) {
            if (static_cast<uint64_t>(dim) > (16U << 20) / count)
                throw std::runtime_error("test tensor exceeds 16M elements");
            count *= static_cast<size_t>(dim);
        }
        std::vector<float> data(count);
        std::ifstream file(argv[3], std::ios::binary);
        if (!file.read(reinterpret_cast<char *>(data.data()), count * sizeof(float)) || file.peek() != EOF)
            throw std::runtime_error("input size mismatch");
        auto mem = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
        auto input = Ort::Value::CreateTensor<float>(mem, data.data(), count, shape.data(), shape.size());
        stage("before cpu_run");
        auto expected = reference.Run(Ort::RunOptions{nullptr}, &in_name, &input, 1, &out_name, 1);
        stage("after cpu_run");
        unsigned repeats=1;
        if (const char *value=std::getenv("BBAI64_REPEAT")) {
            std::string v(value);
            if (v.empty() || v.size()>4 || v.find_first_not_of("0123456789")!=std::string::npos)
                throw std::runtime_error("BBAI64_REPEAT must be 1..1000");
            repeats=static_cast<unsigned>(std::stoul(v));
            if (!repeats || repeats>1000) throw std::runtime_error("BBAI64_REPEAT must be 1..1000");
        }
        std::vector<double> durations;
        std::vector<float> first_output;
        float worst_error=0, output_drift=0;
        for (unsigned iteration=0; iteration<=repeats; ++iteration) {
        stage("before tidl_run");
        const auto run_start = std::chrono::steady_clock::now();
        auto actual = target.Run(Ort::RunOptions{nullptr}, &in_name, &input, 1, &out_name, 1);
        const double elapsed_ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now()-run_start).count();
        stage("after tidl_run");
        auto a = expected[0].GetTensorTypeAndShapeInfo(), b = actual[0].GetTensorTypeAndShapeInfo();
        if (a.GetShape() != b.GetShape() || a.GetElementType() != ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT ||
            b.GetElementType() != ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT || !a.GetElementCount())
            throw std::runtime_error("expected matching float32 outputs");
        const float *x = expected[0].GetTensorData<float>(), *y = actual[0].GetTensorData<float>();
        float max_error = 0;
        for (size_t i = 0; i < a.GetElementCount(); ++i) {
            if (!std::isfinite(x[i]) || !std::isfinite(y[i])) throw std::runtime_error("nonfinite output");
            max_error = std::max(max_error, std::abs(x[i] - y[i]));
        }
        worst_error = std::max(worst_error, max_error);
        if (iteration == 0) first_output.assign(y, y + a.GetElementCount());
        else for (size_t j=0; j<a.GetElementCount(); ++j)
            output_drift=std::max(output_drift,std::abs(y[j]-first_output[j]));
        if (iteration > 0) durations.push_back(elapsed_ms);
        std::cout << "ITERATION index=" << iteration << " warmup=" << (iteration==0)
                  << " run_ms=" << elapsed_ms << " max_abs_error=" << max_error << '\n';
        if (max_error > tolerance) throw std::runtime_error("CPU/TIDL output tolerance exceeded");
        c_api_tidl_benchmark_data bench{};
        stage("before benchmark");
        Ort::ThrowOnError(OrtSessionGetTIBenchmarkData_Tidl(target, &bench));
        stage("after benchmark");
        if (!bench.num_subgraph_data || bench.num_subgraph_data > TIDL_MAX_SUBGRAPH_DATA)
            throw std::runtime_error("missing TIDL subgraph timings");
        bool processed = false;
        for (unsigned i = 0; i < bench.num_subgraph_data; ++i) {
            std::cout << "subgraph " << i << " proc_start=" << bench.proc_start[i]
                      << " proc_end=" << bench.proc_end[i] << '\n';
            processed |= bench.proc_end[i] > bench.proc_start[i];
        }
        if (!processed) throw std::runtime_error("no TIDL processing interval");
        std::cout << "TIDL_BENCHMARK_OK max_abs_error=" << max_error << '\n';
        }
        double total=0;for (double t:durations) total+=t;
        std::cout << "REPEAT_OK warmup=1 measured=" << repeats << " mean_ms=" << total/durations.size()
                  << " min_ms=" << *std::min_element(durations.begin(),durations.end())
                  << " max_ms=" << *std::max_element(durations.begin(),durations.end())
                  << " worst_abs_error=" << worst_error << " drift_from_first=" << output_drift << '\n';
        return 0;
    } catch (const std::exception &e) {
        std::cerr << e.what() << '\n';
        return 1;
    }
}
