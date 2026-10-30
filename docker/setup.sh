#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
source_revision=f4ee780ee7bb33da5325901d6d1965eda3221033
evf_revision=9935dc52571678b806830821b3ddeacb30e7af07
github_ssh="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15}"
export GIT_SSH_COMMAND="$github_ssh"
scenes=(arc bahai buddha castle christ church outpost pagoda pisa_cathedral sacre_coeur sant schloss statue temple tower windmill)

die() { echo "FlyCo setup: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing host command: $1"; }
has_hash() { [[ -s "$1" ]] && [[ "$(sha256sum "$1" | cut -d ' ' -f 1)" == "$2" ]]; }

preflight() {
  need git; need curl; need python3; need sha256sum; need docker; need nvidia-smi
  [[ "$(uname -m)" == x86_64 ]] || die "An x86_64 Linux host is required"
  [[ -n "${DISPLAY:-}" ]] || die "An X11 display is required; set DISPLAY before setup"
  if [[ "$DISPLAY" == :* ]]; then
    local display_num="${DISPLAY#:}"
    display_num="${display_num%%.*}"
    [[ -S "/tmp/.X11-unix/X$display_num" ]] || die "X11 socket for DISPLAY=$DISPLAY is missing"
  fi
  docker info >/dev/null || die "Docker Engine is not available to this account"
  nvidia-smi >/dev/null || die "NVIDIA driver or GPU is unavailable"
  export TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST:-$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -n 1)}"
  [[ "$TORCH_CUDA_ARCH_LIST" =~ ^[0-9]+\.[0-9]+$ ]] || die "Cannot detect GPU compute capability; set TORCH_CUDA_ARCH_LIST manually"

  local install_root="$root" available_kib ue_ref
  [[ -d "$root/planner_simulator" ]] || install_root="$root/FlyCo"
  if [[ ! -d "$install_root/.docker-data/UnrealEngine/.git" ]]; then
    available_kib="$(df -Pk "$root" | awk 'END {print $4}')"
    (( available_kib >= 150 * 1024 * 1024 )) || die "At least 150 GiB of free disk space is required for a new UE build"
    echo "Checking GitHub access to UnrealEngine 4.25..."
    ue_ref="$(git ls-remote ssh://git@ssh.github.com:443/EpicGames/UnrealEngine.git refs/heads/4.25)" ||
      die "UE4.25 GitHub access failed. Link Epic and GitHub, authorize EpicGames, accept its invitation, then configure GitHub SSH: https://www.unrealengine.com/en-US/ue-on-github"
    [[ -n "$ue_ref" ]] || die "UE4.25 branch is unavailable to this GitHub account: https://www.unrealengine.com/en-US/ue-on-github"
  fi
  docker run --rm --gpus all --entrypoint nvidia-smi nvidia/cuda:11.8.0-devel-ubuntu20.04 >/dev/null ||
    die "Docker GPU access failed; install/configure the NVIDIA Container Toolkit"
}

if [[ "${1:-}" != --check ]]; then
  [[ $# -eq 0 ]] || die "Usage: $0 [--check]"
  preflight
fi

if [[ ! -d "$root/planner_simulator" ]]; then
  if [[ "${1:-}" == --check ]]; then
    [[ -f "$root/FlyCo/docker/setup.sh" ]] || die "No FlyCo source beside $here; run setup without --check first"
    exec bash "$root/FlyCo/docker/setup.sh" --check
  fi
  target="$root/FlyCo"
  if [[ ! -d "$target/.git" ]]; then
    [[ ! -e "$target" ]] || die "$target exists without a Git checkout"
    git clone --progress --depth 1 ssh://git@ssh.github.com:443/FC-Family/FlyCo.git "$target"
    if [[ "$(git -C "$target" rev-parse HEAD)" != "$source_revision" ]]; then
      git -C "$target" fetch --depth 1 origin "$source_revision"
    fi
    git -C "$target" checkout --detach "$source_revision"
    mkdir -p "$target/docker"
    cp -a "$here/." "$target/docker/"
    cp -a "$here/overrides/." "$target/"
    rm -f "$target"/perception_predictor/scripts/run_percept_*.sh
    rm -f "$target/perception_predictor/scripts/start_percept_refactor.zsh"
    find "$target/planner_simulator/src/flyco_planner_manager/launch/demo" -maxdepth 1 -type f -name 'flyco_planner_*.launch' -delete
    [[ ! -d "$target/perception_predictor/src/sam_tracking/tests" ]] || find "$target/perception_predictor/src/sam_tracking/tests" -depth -delete
  else
    [[ -d "$target/planner_simulator" ]] || die "$target is an incomplete checkout"
    if [[ ! -f "$target/docker/setup.sh" ]]; then
      if [[ "$(git -C "$target" rev-parse HEAD)" != "$source_revision" ]]; then
        git -C "$target" fetch --depth 1 origin "$source_revision"
      fi
      git -C "$target" checkout --detach "$source_revision"
      cp -a "$here/overrides/." "$target/"
      rm -f "$target"/perception_predictor/scripts/run_percept_*.sh
      rm -f "$target/perception_predictor/scripts/start_percept_refactor.zsh"
      find "$target/planner_simulator/src/flyco_planner_manager/launch/demo" -maxdepth 1 -type f -name 'flyco_planner_*.launch' -delete
      [[ ! -d "$target/perception_predictor/src/sam_tracking/tests" ]] || find "$target/perception_predictor/src/sam_tracking/tests" -depth -delete
    fi
    mkdir -p "$target/docker"
    cp -a "$here/." "$target/docker/"
  fi
  exec bash "$target/docker/setup.sh" "$@"
fi

data="$root/.docker-data"
engine="$data/UnrealEngine"
project="$data/FlyCoUE"
models="$root/perception_predictor/src/mesh_predict/resources/checkpoints"
sam="$root/perception_predictor/src/sam_tracking/ckpt/sam2_hiera_small.pt"
mesh="$models/checkpoint.pt"
mesh_url="${FLYCO_CHECKPOINT_URL:-https://drive.usercontent.google.com/download?id=1nCyX6wP0Ni7W1TAi_lJ2k__bSu8FviNo&export=download&confirm=t}"
nksr="$models/snet-n3k-wonormal.pth"
sam_hash=95949964d4e548409021d47b22712d5f1abf2564cc0c3c765ba599a24ac7dce3
mesh_hash=2918f477e651eb8d5cead60ce92f17f8de8889958a45ebaa20543dfac99a3677
nksr_hash=3a6454d9bbd5111fbac04bb83f966e1597782f9ec72bad889925b992e07bdb6f
evf_hash=de5ea4da5236e386ca1c7f5eba51d008f10082d433d9bb354050721701f2e5db

ue_ready() {
  [[ -x "$engine/Engine/Binaries/Linux/UE4Editor" &&
     -x "$engine/Engine/Binaries/Linux/ShaderCompileWorker" &&
     -f "$project/Binaries/Linux/libUE4Editor-Blocks.so" &&
     -f "$project/Plugins/AirSim/Binaries/Linux/libUE4Editor-AirSim.so" ]]
}

check() {
  ue_ready || die "UE editor or FlyCo project binaries are incomplete"
  [[ -f "$project/FlyCo.uproject" && -f "$project/Plugins/AirSim/AirSim.uplugin" ]] || die "FlyCo UE project is incomplete under $project"
  python3 - "$here/assets" "$project" <<'PY' || die "Scene or common asset is missing or corrupt"
import json
import pathlib
import sys

for manifest in pathlib.Path(sys.argv[1]).glob("*.json"):
    for item in json.loads(manifest.read_text()):
        asset = pathlib.Path(sys.argv[2], item["path"])
        if not asset.is_file() or asset.open("rb").read(4) != b"\xc1\x83\x2a\x9e":
            sys.exit(f"Missing or invalid asset: {asset}")
PY
  for scene in "${scenes[@]}"; do
    [[ -n "$(find "$project/Content/scenarios/$scene" -name "$scene.umap" -print -quit 2>/dev/null)" ]] || die "Missing map: $scene"
  done
  has_hash "$sam" "$sam_hash" || die "SAM2 checkpoint is missing or corrupt"
  has_hash "$mesh" "$mesh_hash" || die "Mesh checkpoint is missing or corrupt"
  has_hash "$nksr" "$nksr_hash" || die "NKSR checkpoint is missing or corrupt"
  [[ -d "$data/hf-cache/hub/models--facebook--dinov2-base/snapshots" ]] || die "DINOv2 cache is missing"
  [[ -d "$data/hf-cache/hub/models--google--siglip-base-patch16-224/snapshots" ]] || die "SigLIP cache is missing"
  [[ -f "$data/home/workspace/EVF-SAM/inference.py" ]] || die "EVF-SAM source is missing"
  [[ -d "$data/hf-cache/hub/models--YxZhang--evf-sam2/snapshots" ]] || die "EVF-SAM2 cache is missing"
  evf_model="$(find "$data/hf-cache/hub/models--YxZhang--evf-sam2/snapshots" -name model.safetensors -print -quit)"
  has_hash "$evf_model" "$evf_hash" || die "EVF-SAM2 model is missing or corrupt"
  for image in flyco:noetic flyco:full flyco:ue-build; do
    docker image inspect "$image" >/dev/null 2>&1 || die "Docker image is missing: $image"
  done
  echo "FlyCo setup is complete. Run: $root/docker/run.sh bahai"
}

if [[ "${1:-}" == --check ]]; then
  [[ $# -eq 1 ]] || die "Usage: $0 [--check]"
  need docker; need sha256sum; need python3
  check
  exit
fi
mkdir -p "$data" "$models" "$(dirname "$sam")"

if [[ ! -d "$engine/.git" ]]; then
  [[ ! -e "$engine" ]] || die "$engine exists but is not a Git checkout"
  echo "Cloning EpicGames/UnrealEngine 4.25 (Epic-linked GitHub access required)..."
  git clone --progress --depth 1 --branch 4.25 --single-branch ssh://git@ssh.github.com:443/EpicGames/UnrealEngine.git "$engine" ||
    die "UE clone failed. Link Epic and GitHub, accept the invitation, and configure GitHub SSH access."
fi

download_project() {
  echo "Preparing cached Google Drive downloader..."
  docker run --rm --network host --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -e PYTHONPATH=/data/tools/gdown -e DOWNLOAD_TIMEOUT -e DOWNLOAD_RETRIES -e DOWNLOAD_JOBS \
    -e HTTP_PROXY -e HTTPS_PROXY -e ALL_PROXY -e NO_PROXY \
    -e http_proxy -e https_proxy -e all_proxy -e no_proxy \
    -v "$data:/data" -v "$here:/setup:ro" python:3.12-slim \
    sh -ec 'python -c "import gdown; assert gdown.__version__ == \"6.4.2\"" 2>/dev/null ||
      python -m pip install --disable-pip-version-check --timeout 30 --retries 3 \
        --upgrade --target /data/tools/gdown "gdown==6.4.2"
      exec python -u /setup/download-project.py /data'
}

if [[ ! -f "$project/FlyCo.uproject" || ! -f "$project/Plugins/AirSim/AirSim.uplugin" ]]; then
  stage="$data/project-download"
  mkdir -p "$stage"
  echo "Downloading the FlyCo UE project from Google Drive..."
  download_project
  uproject="$(find "$stage" -name FlyCo.uproject -type f -print -quit)"
  [[ -n "$uproject" ]] || die "Google Drive download did not contain FlyCo.uproject under $stage"
  mkdir -p "$project"
  cp -a "$(dirname "$uproject")/." "$project/"
fi
[[ -f "$project/Plugins/AirSim/AirSim.uplugin" ]] || die "FlyCo UE project lacks Plugins/AirSim/AirSim.uplugin"
if [[ -n "${stage:-}" ]]; then
  rm -rf -- "$stage"
fi

echo "Checking all 16 scene maps and common assets..."
for manifest in scenes bahai misc; do
  bash "$here/download-manifest.sh" "$here/assets/$manifest.json" "$project"
done

if ! has_hash "$sam" "$sam_hash"; then
  echo "Downloading SAM2 checkpoint..."
  curl -fL --retry 5 --retry-all-errors --connect-timeout 30 --speed-limit 1 --speed-time 60 \
    'https://dl.fbaipublicfiles.com/segment_anything_2/072824/sam2_hiera_small.pt' -o "$sam.part"
  has_hash "$sam.part" "$sam_hash" || die "SAM2 download failed checksum verification"
  mv "$sam.part" "$sam"
fi
if ! has_hash "$mesh" "$mesh_hash"; then
  [[ -n "$mesh_url" ]] || die "Set FLYCO_CHECKPOINT_URL to the checkpoint download URL, or place checkpoint.pt under $models"
  echo "Downloading mesh checkpoint..."
  curl -fL --retry 5 --retry-all-errors --connect-timeout 30 --speed-limit 1 --speed-time 60 \
    --continue-at - "$mesh_url" -o "$data/checkpoint.pt.part"
  has_hash "$data/checkpoint.pt.part" "$mesh_hash" || die "Checkpoint download failed checksum verification"
  mv "$data/checkpoint.pt.part" "$mesh"
fi
rm -f "$models/checkpoint.pth"
if ! has_hash "$nksr" "$nksr_hash"; then
  echo "Downloading NKSR checkpoint..."
  curl -fL --retry 5 --retry-all-errors --connect-timeout 30 --speed-limit 1 --speed-time 60 \
    'https://huggingface.co/heiwang1997/nksr-checkpoints/resolve/main/checkpoints/snet-n3k-wonormal.pth' -o "$nksr.part"
  has_hash "$nksr.part" "$nksr_hash" || die "NKSR download failed checksum verification"
  mv "$nksr.part" "$nksr"
fi

evf_root="$data/home/workspace/EVF-SAM"
if [[ ! -f "$evf_root/inference.py" ]]; then
  [[ ! -e "$evf_root" ]] || die "$evf_root exists but lacks inference.py"
  mkdir -p "$(dirname "$evf_root")"
  git clone --depth 1 ssh://git@ssh.github.com:443/hustvl/EVF-SAM.git "$evf_root" ||
    die "EVF-SAM source download failed; rerun setup when GitHub is reachable"
  if [[ "$(git -C "$evf_root" rev-parse HEAD)" != "$evf_revision" ]]; then
    git -C "$evf_root" fetch --depth 1 origin "$evf_revision"
    git -C "$evf_root" checkout --detach "$evf_revision"
  fi
fi

for spec in 'docker/Dockerfile flyco:noetic' 'docker/Dockerfile.ml flyco:full' 'docker/Dockerfile.ue flyco:ue-build'; do
  read -r dockerfile image <<< "$spec"
  if ! docker image inspect "$image" >/dev/null 2>&1; then
    build_args=(--network=host -f "$root/$dockerfile" -t "$image")
    [[ "$image" == flyco:full ]] && build_args+=(--build-arg "TORCH_CUDA_ARCH_LIST=$TORCH_CUDA_ARCH_LIST")
    if [[ "$image" == flyco:ue-build && -n "${FLYCO_APT_PROXY:-}" ]]; then
      build_args+=(--build-arg "APT_PROXY=$FLYCO_APT_PROXY")
    fi
    docker build "${build_args[@]}" "$root"
  fi
done
if ! ue_ready; then
  bash "$here/build-ue.sh"
fi

mkdir -p "$data/hf-cache"
if [[ ! -d "$data/hf-cache/hub/models--facebook--dinov2-base/snapshots" ||
      ! -d "$data/hf-cache/hub/models--google--siglip-base-patch16-224/snapshots" ||
      ! -d "$data/hf-cache/hub/models--YxZhang--evf-sam2/snapshots" ]]; then
  docker run --rm --user "$(id -u):$(id -g)" -e HOME=/home/flyco -e HF_ENDPOINT \
    -v "$data/hf-cache:/home/flyco/.cache/huggingface" flyco:full python3 -c \
    'from huggingface_hub import snapshot_download; snapshot_download("facebook/dinov2-base"); snapshot_download("google/siglip-base-patch16-224"); snapshot_download("YxZhang/evf-sam2")'
fi
check
