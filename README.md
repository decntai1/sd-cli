# sd-cli - multi-arch stable-diffusion.cpp builds (incl. Blackwell)

Prebuilt `sd-cli` binaries from leejet/stable-diffusion.cpp @ `master-656-0e4ee04`,
plus the build recipe. Two CUDA variants, both carrying `sm_120` (Blackwell):

| binary        | toolkit | arches (real + PTX)                  | driver floor  |
|---------------|---------|--------------------------------------|---------------|
| `sd-cli-cu12` | 12.8    | 70 75 80 86 89 90 100 120 (+120 PTX) | sm_70 (Volta) |
| `sd-cli-cu13` | 13.0    | 75 80 86 89 90 100 120 (+120 PTX)    | sm_75 (Turing)|

Download from **Releases**. Dynamically linked against the CUDA runtime
(cudart/cublas/nccl) - same as upstream - so run on a box where those are on
the loader path (a PyTorch/CUDA image, or `pip install nvidia-cuda-runtime-cu12
nvidia-cublas-cu12 nvidia-nccl-cu12` + LD_LIBRARY_PATH). Build it yourself via
the included Dockerfiles + `build-and-validate-sd-cli.sh`.

## License
Build recipe: MIT (see LICENSE). Binaries derive from stable-diffusion.cpp and
ggml, both MIT - see NOTICE.
