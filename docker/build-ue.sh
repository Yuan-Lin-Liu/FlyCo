#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
engine="$root/.docker-data/UnrealEngine"
project="$root/.docker-data/FlyCoUE"
[[ -d "$engine/.git" && -f "$project/FlyCo.uproject" ]] || {
  echo "Missing UE4.25 source or FlyCo.uproject under .docker-data" >&2
  exit 1
}
args=(--rm --network host --user "$(id -u):$(id -g)" -e HOME=/tmp
  -v "$engine:/opt/UnrealEngine" -v "$project:/opt/FlyCoUE" -w /opt/UnrealEngine)

if [[ ! -f "$engine/Engine/Source/ThirdParty/Linux/HaveLinuxDependencies" ]]; then
  docker run "${args[@]}" flyco:ue-build \
    bash Engine/Build/BatchFiles/Linux/GitDependencies.sh --force --threads=16
  [[ -f "$engine/Engine/Source/ThirdParty/Linux/HaveLinuxDependencies" ]]
fi

toolchain="$engine/Engine/Extras/ThirdPartyNotUE/SDKs/HostLinux/Linux_x64/v16_clang-9.0.1-centos7"
if [[ ! -x "$toolchain/x86_64-unknown-linux-gnu/bin/clang++" ]]; then
  docker run "${args[@]}" flyco:ue-build \
    bash Engine/Build/BatchFiles/Linux/SetupToolchain.sh
fi

ionic="$engine/Engine/Binaries/DotNET/Ionic.Zip.Reduced.dll"
[[ -e "$ionic" ]] || ln -s ../ThirdParty/Ionic/Ionic.Zip.Reduced.dll "$ionic"

docker run "${args[@]}" flyco:ue-build bash ./GenerateProjectFiles.sh
docker run "${args[@]}" flyco:ue-build \
  bash Engine/Build/BatchFiles/Linux/Build.sh UE4Editor Linux Development
docker run "${args[@]}" flyco:ue-build \
  bash Engine/Build/BatchFiles/Linux/Build.sh ShaderCompileWorker Linux Development
docker run "${args[@]}" flyco:ue-build \
  bash Engine/Build/BatchFiles/Linux/Build.sh BlocksEditor Linux Development \
  -project=/opt/FlyCoUE/FlyCo.uproject
