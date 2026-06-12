#!/usr/bin/env bash
# build-and-validate-sd-cli.sh
# ===========================================================================
# OPERATOR script. Run this ON A REAL BLACKWELL (RTX 50-series, sm_120) NODE
# that has Docker + the NVIDIA container toolkit. It:
#   1. Builds BOTH arch-correct sd-cli images (cu12 + cu13).
#   2. Extracts BOTH binaries to ./dist/ locally (no container left running).
#   3. Runs a REAL generation with the arch-matching binary against a small
#      sdcpp model and greps the output for "no kernel image" / failure.
#      (NOT `--help` — that never loads a CUDA kernel and would falsely pass.)
#   4. PRINTS (does NOT perform) the final scp to the VPS downloads/ dir, plus
#      the Ada/Ampere regression-test reminder.
#
# This script never scp's, never touches the live /download/sd-cli-* binaries,
# and never runs on the VPS. It builds + validates only. The live swap is a
# deliberate, separate, manual step you perform AFTER the checks below pass.
#
# DISK NOTE: the CUDA *-devel base images are several GB each; both builds plus
# layers can exceed ~30 GB. Point Docker's data-root at a big volume first, e.g.
#   sudo mkdir -p /mnt/big/docker
#   echo '{"data-root":"/mnt/big/docker"}' | sudo tee /etc/docker/daemon.json
#   sudo systemctl restart docker
# ===========================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST="${HERE}/dist"
mkdir -p "${DIST}"

# --- Tunables (override via env) -------------------------------------------
# A small sdcpp model + a real generation command. sd-cli MUST actually load a
# CUDA kernel for this to prove sm_120 works, so point MODEL at a small checkpoint
# already on this box (e.g. an SD1.5 / z-image GGUF). Adjust GEN_ARGS to whatever
# minimal valid invocation your model needs.
MODEL="${MODEL:-/workspace/models/sd-v1-5.safetensors}"
GEN_PROMPT="${GEN_PROMPT:-a red apple on a table}"
GEN_OUT="${GEN_OUT:-${DIST}/_validate_out.png}"
# Keep it tiny + fast: small res, few steps. Override if your model needs more.
GEN_ARGS="${GEN_ARGS:---steps 4 -W 256 -H 256 --cfg-scale 1.0}"

VPS_USER="${VPS_USER:-youruser}"
VPS_HOST="${VPS_HOST:-your.server.example}"
VPS_DLDIR="${VPS_DLDIR:-/path/to/your/downloads}"

CU12_IMG="decntai/sd-cli-build:cu12"
CU13_IMG="decntai/sd-cli-build:cu13"

say() { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }
warn() { printf '\033[1;33m%s\033[0m\n' "$*"; }
die() { printf '\033[1;31mFATAL: %s\033[0m\n' "$*" >&2; exit 1; }

command -v docker >/dev/null || die "docker not found"
command -v nvidia-smi >/dev/null || warn "nvidia-smi not found — is this a GPU box?"

# --- 1. Build both images --------------------------------------------------
say "Building cu12 image (${CU12_IMG})"
docker build -f "${HERE}/Dockerfile.sd-cli-cu12" -t "${CU12_IMG}" "${HERE}" \
  || die "cu12 build failed (check the nvcc --list-gpu-arch printout vs CUDA_ARCHS)"

say "Building cu13 image (${CU13_IMG})"
docker build -f "${HERE}/Dockerfile.sd-cli-cu13" -t "${CU13_IMG}" "${HERE}" \
  || die "cu13 build failed (check the nvcc --list-gpu-arch printout vs CUDA_ARCHS)"

# --- 2. Extract both binaries to ./dist ------------------------------------
extract() {  # $1=image  $2=dest
  local cid
  cid="$(docker create "$1")" || die "docker create $1 failed"
  docker cp "${cid}:/out/sd-cli" "$2" || { docker rm -f "${cid}" >/dev/null; die "cp from $1 failed"; }
  docker rm -f "${cid}" >/dev/null
  chmod 755 "$2"
  printf '  extracted %s (%s MB)\n' "$2" "$(( $(stat -c%s "$2") / 1024 / 1024 ))"
}
say "Extracting binaries to ${DIST}"
extract "${CU12_IMG}" "${DIST}/sd-cli-cu12"
extract "${CU13_IMG}" "${DIST}/sd-cli-cu13"

# --- 3. REAL generation with the arch-matching binary ----------------------
# Pick the binary by host CUDA major (mirrors setup.py's fetch logic).
CUDA_MAJOR="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1 | cut -d. -f1)"
# driver_version major != CUDA major; the reliable signal is `nvcc` if present,
# else fall back to the CUDA runtime reported by nvidia-smi.
if command -v nvcc >/dev/null; then
  TK_MAJOR="$(nvcc --version | grep -oE 'release [0-9]+' | grep -oE '[0-9]+' | head -n1)"
else
  TK_MAJOR="$(nvidia-smi | grep -oE 'CUDA Version: [0-9]+' | grep -oE '[0-9]+' | head -n1)"
fi
TK_MAJOR="${TK_MAJOR:-12}"
if [ "${TK_MAJOR}" -ge 13 ]; then
  VAL_BIN="${DIST}/sd-cli-cu13"; VAL_ARCH="cu13"
else
  VAL_BIN="${DIST}/sd-cli-cu12"; VAL_ARCH="cu12"
fi

# --- 3a. Runtime flag check (functional — moved OUT of the Dockerfiles) -------
# THIS is the right place to run the binary: this is a GPU box (libcuda present),
# unlike the docker BUILD sandbox where `--help` can fail to init CUDA and error
# before printing. The Dockerfiles only do a GPU-free `strings` smoke; here we
# assert all four required flags actually surface in --help on real hardware.
say "Runtime flag check: ${VAL_ARCH} --help must list all four required flags"
HELP_OUT="$("${VAL_BIN}" --help 2>&1 || true)"
for f in '--ref-image' '--llm_vision' 'vid_gen' '--diffusion-fa'; do
  echo "${HELP_OUT}" | grep -qF -- "$f" \
    || die "Required flag '$f' absent from ${VAL_ARCH} --help — wrong/old ref? Do NOT ship."
done
say "All four required flags present in ${VAL_ARCH} --help"

say "Validating ${VAL_ARCH} binary on THIS GPU with a real generation"
if [ ! -f "${MODEL}" ]; then
  warn "MODEL not found at ${MODEL}."
  warn "Set MODEL=/path/to/a/small/sdcpp/checkpoint and re-run. CANNOT validate"
  warn "sm_120 without loading a real CUDA kernel — skipping gen, build NOT proven."
  exit 2
fi

rm -f "${GEN_OUT}"
GEN_LOG="${DIST}/_validate_${VAL_ARCH}.log"
# shellcheck disable=SC2086
"${VAL_BIN}" -m "${MODEL}" -p "${GEN_PROMPT}" -o "${GEN_OUT}" ${GEN_ARGS} \
  > "${GEN_LOG}" 2>&1
GEN_RC=$?

echo "  exit=${GEN_RC}  log=${GEN_LOG}"
if grep -qiE 'no kernel image|invalid device function|CUDA error|out of memory|failed' "${GEN_LOG}"; then
  warn "---- offending log lines ----"
  grep -niE 'no kernel image|invalid device function|CUDA error|out of memory|failed' "${GEN_LOG}" | sed 's/^/    /'
  die "Generation reported a CUDA/kernel failure on sm_120 — the fat binary is NOT good. Do NOT ship."
fi
if [ "${GEN_RC}" -ne 0 ] || [ ! -s "${GEN_OUT}" ]; then
  die "Generation exited ${GEN_RC} or produced no output (${GEN_OUT}). Do NOT ship."
fi
say "VALIDATION PASSED on Blackwell (${VAL_ARCH}) — real image written to ${GEN_OUT}"

# --- 4. Next steps: PRINT ONLY (no scp performed here) ---------------------
cat <<EOF

============================================================================
 NEXT STEPS — performed MANUALLY by you, NOT by this script
============================================================================
 1) REGRESSION TEST FIRST. Before any live swap, run the SAME real generation
    with the matching binary on an Ada (sm_89, e.g. RTX 4060) AND an Ampere
    (sm_86, e.g. RTX 3060) box. The fat binary MUST still work there — it is a
    strict superset, not a replacement. If either regresses, do NOT ship.

 2) Only after Blackwell PASS + Ada/Ampere regression PASS, copy the binaries
    to the VPS (this script does NOT do this for you):

      scp ${DIST}/sd-cli-cu12  ${VPS_USER}@${VPS_HOST}:${VPS_DLDIR}/sd-cli-cu12
      scp ${DIST}/sd-cli-cu13  ${VPS_USER}@${VPS_HOST}:${VPS_DLDIR}/sd-cli-cu13
      ssh ${VPS_USER}@${VPS_HOST} 'chmod 755 ${VPS_DLDIR}/sd-cli-cu12 ${VPS_DLDIR}/sd-cli-cu13'

 3) Confirm they serve:
      curl -sI https://ai.decntai.com/download/sd-cli-cu12   # expect 200
      curl -sI https://ai.decntai.com/download/sd-cli-cu13   # expect 200

 New providers fetch these via setup.py fetch_or_build_sdcli (cu13 when host
 CUDA major >= 13, else cu12). Existing providers re-run setup.py / re-fetch.
============================================================================
EOF
