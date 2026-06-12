---
license: mit
tags:
- stable-diffusion
- stable-diffusion-cpp
- cuda
- blackwell
- ggml
---
# sd-cli — multi-arch stable-diffusion.cpp builds (incl. Blackwell)

Prebuilt `sd-cli` binaries from leejet/stable-diffusion.cpp @ `master-656-0e4ee04`,
plus the build recipe. Two CUDA variants, each a fat binary covering every NVIDIA
GPU architecture from its floor up through Blackwell.

## Supported GPU architectures

| SM     | Architecture   | Example GPUs                          | cu12 | cu13 |
|--------|----------------|---------------------------------------|:----:|:----:|
| sm_70  | Volta          | Tesla V100, Titan V                   |  yes |  no  |
| sm_75  | Turing         | RTX 20-series, GTX 16-series, T4      |  yes |  yes |
| sm_80  | Ampere (DC)    | A100, A30                             |  yes |  yes |
| sm_86  | Ampere         | RTX 30-series, A40, A10, A2000        |  yes |  yes |
| sm_89  | Ada Lovelace   | RTX 40-series, L4, L40S               |  yes |  yes |
| sm_90  | Hopper         | H100, H200, GH200                     |  yes |  yes |
| sm_100 | Blackwell (DC) | B100, B200, GB200                     |  yes |  yes |
| sm_120 | Blackwell      | RTX 50-series, RTX PRO 6000 Blackwell |  yes |  yes |

Both binaries also embed sm_120 **PTX** (virtual arch), so they JIT-forward onto
future architectures. Use **cu12** for older drivers / Volta; **cu13** for
CUDA-13 hosts (Volta was dropped upstream in CUDA 13).

## Usage

Download from the **Files** tab (here) or **Releases** (GitHub). Dynamically
linked against the CUDA runtime (cudart/cublas/nccl) — same as upstream — so run
on a box where those libs are on the loader path (a PyTorch/CUDA image, or
`pip install nvidia-cuda-runtime-cu12 nvidia-cublas-cu12 nvidia-nccl-cu12` +
`LD_LIBRARY_PATH`).

    sd-cli-cu12 -m model.gguf -p "a lovely cat" -o out.png

Build it yourself via the included Dockerfiles + `build-and-validate-sd-cli.sh`.

## License
Build recipe: MIT (see LICENSE). Binaries derive from stable-diffusion.cpp and
ggml, both MIT — see NOTICE.
