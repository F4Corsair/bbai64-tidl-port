# ResNet18 Compilation SIGBUS Investigation

## Findings

**Exhaustion of Docker's64MiB shared-memory limit is considered the immediate cause.** Reproduced with the same image and official ResNet18 settings. Expansion had not yet been tested at the initial investigation stage.

| Item | Observation |
|---|---|
| Image | bbai64-tidl:11_02_04_00-j721e |
| Execution | Official basic_example, onnxrt, cl-ort-resnet18-v1, --compile |
| Settings | SOC=J721E, CPU Tools,8-bit, calibration_frames=2, iterations=5 |
| Initial /dev/shm | 64MiB,0 used |
| Failure point | Immediately after tivxInit Initialization Done |
| Termination | SIGBUS, process exit 135 |
| /dev/shm after failure | 64MiB used,100%,0 free |
| Shared files | vashm_buff_*_0 approximately370KiB; vashm_buff_*_1 approximately80MiB |

Preserved [reproduction log](logs/resnet18-sigbus.log) and [container/options inspection](logs/container-inspection.log). The --rm reproduction container exited. No commands changed models/inputs in persistent work storage.

## Interpretation

At the time of failure, compose.yaml did not specify shm_size; measured /dev/shm was64MiB. The host-emulation allocator creates shared files, ftruncates them, and accesses them via mmap. Creation/truncation can succeed even when logical size exceeds available tmpfs space; touching pages after capacity exhaustion can raise SIGBUS. The same run had an80MiB shared file and exhausted64MiB tmpfs. Relevant SDK code: app_utils/utils/mem/src/app_mem_pc.c, mmap near296 and ftruncate near679.

Docker preparation had not validated model-compilation shared-memory requirements or set an explicit size. ORT/Tools version checks passed, but an actual compilation test was also necessary.

## Proposed remedy and acceptance criteria

Add shm_size: "1gb" to compiler in Compose. This is diagnostic headroom, not the model's measured minimum. Host RAM is consumed according to touched pages. Rebuilding the image is unnecessary; create a new container.

After user review, rerun once with the same model/version/calibration, changing only /dev/shm to1GiB. Require exit 0, generated artifacts, and no SIGBUS. On failure, collect exit code/first error/shared-memory usage before investigating further.

Before review, neither Compose capacity nor compilation with expanded memory was changed.

## Result after applying the fix

With shm_size set to1GiB, the same official model compiled with exit 0 and host TIDL inference passed. Model/artifacts/preprocessed input/CPU and host-TIDL outputs are in tidl/ready/resnet18. Its README records maximum host error and the board-test tolerance.
