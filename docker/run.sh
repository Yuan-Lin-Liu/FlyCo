#!/usr/bin/env bash
set -euo pipefail

scene="${1:-bahai}"
[[ "$scene" =~ ^[a-z0-9_]+$ ]] || { echo "Invalid scene name: $scene" >&2; exit 2; }
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
engine="$root/.docker-data/UnrealEngine"
project="$root/.docker-data/FlyCoUE"
map_file="$(find "$project/Content/scenarios/$scene" -name "$scene.umap" -print -quit 2>/dev/null || true)"

[[ -x "$engine/Engine/Binaries/Linux/UE4Editor" ]] || {
  echo "UE4Editor is not built under $engine" >&2
  exit 1
}
[[ -f "$project/FlyCo.uproject" && -n "$map_file" ]] || {
  echo "Missing FlyCo UE project or $scene map under $project" >&2
  exit 1
}
for required in \
  "$root/perception_predictor/src/sam_tracking/ckpt/sam2_hiera_small.pt" \
  "$root/perception_predictor/src/mesh_predict/resources/checkpoints/checkpoint.pt" \
  "$root/perception_predictor/src/mesh_predict/resources/checkpoints/snet-n3k-wonormal.pth" \
  "$root/.docker-data/hf-cache/hub/models--facebook--dinov2-base/snapshots" \
  "$root/.docker-data/hf-cache/hub/models--google--siglip-base-patch16-224/snapshots"; do
  [[ -e "$required" ]] || { echo "Missing model resource: $required" >&2; exit 1; }
done
[[ -n "${DISPLAY:-}" ]] || { echo "DISPLAY is not set" >&2; exit 1; }

map_name="/Game/${map_file#"$project/Content/"}"
map_name="${map_name%.umap}"
mkdir -p "$root/.docker-data/home/.cache" "$root/.docker-data/home/.ros" \
  "$root/.docker-data/home/Documents" \
  "$root/.docker-data/hf-cache" "$root/.docker-data/logs/planner" \
  "$root/.docker-data/logs/ros" "$root/.docker-data/logs/ue"
touch "$root/.docker-data/home/.zshrc"

args=(--rm -it --name "flyco-$scene" --network host --ipc host --gpus all
  --user "$(id -u):$(id -g)" -e HOME=/home/flyco
  -e DISABLE_ROS1_EOL_WARNINGS=1
  -e DISPLAY -e NVIDIA_DRIVER_CAPABILITIES=graphics,utility,compute,display
  -e "FLYCO_SCENE=$scene" -e "FLYCO_MAP=$map_name"
  -v /tmp/.X11-unix:/tmp/.X11-unix
  -v "$engine:/opt/UnrealEngine"
  -v "$project:/opt/FlyCoUE"
  -v "$root/.docker-data/home:/home/flyco"
  -v "$root/.docker-data/hf-cache:/home/flyco/.cache/huggingface"
  -v "$root/.docker-data/logs/planner:/opt/flyco/planner_simulator/run_log"
  -v "$root/.docker-data/logs/ros:/home/flyco/.ros/log"
  -v "$root/.docker-data/logs/ue:/var/log/flyco"
  -v "$root/planner_simulator/script/setting:/home/flyco/Documents/AirSim:ro"
  -v "$root/planner_simulator/src/flyco_planner_manager/launch/demo/param.xml:/opt/flyco/planner_simulator/src/flyco_planner_manager/launch/demo/param.xml:ro"
  -v "$root/perception_predictor/src/sam_tracking/ckpt:/opt/flyco/perception_predictor/src/sam_tracking/ckpt:ro"
  -v "$root/perception_predictor/src/mesh_predict/resources/checkpoints:/opt/flyco/perception_predictor/src/mesh_predict/resources/checkpoints:ro")
[[ -d /dev/dri ]] && args+=(--mount type=bind,src=/dev/dri,dst=/dev/dri)
[[ -e /dev/input/js0 ]] && args+=(--device /dev/input/js0)
[[ -f "${XAUTHORITY:-}" ]] && args+=(-e XAUTHORITY=/tmp/.Xauthority -v "$XAUTHORITY:/tmp/.Xauthority:ro")

docker run "${args[@]}" flyco:full bash -lc '
  set -euo pipefail
  source /opt/flyco/perception_predictor/devel/setup.bash
  /opt/UnrealEngine/Engine/Binaries/Linux/UE4Editor \
    /opt/FlyCoUE/FlyCo.uproject "$FLYCO_MAP" -game -windowed -ResX=1280 -ResY=720 \
    > /var/log/flyco/ue.log 2>&1 &
  ue_pid=$!
  trap '\''/opt/flyco/scripts/kill.sh >/dev/null 2>&1 || true; kill "$ue_pid" 2>/dev/null || true'\'' EXIT
  for attempt in {1..900}; do
    if (echo >/dev/tcp/127.0.0.1/41451) 2>/dev/null; then break; fi
    if ! kill -0 "$ue_pid" 2>/dev/null; then tail -n 40 /var/log/flyco/ue.log; exit 1; fi
    sleep 2
  done
  if ! (echo >/dev/tcp/127.0.0.1/41451) 2>/dev/null; then
    tail -n 40 /var/log/flyco/ue.log
    echo "AirSim RPC did not start on port 41451" >&2
    exit 1
  fi
  cd /opt/flyco
  ./scripts/run.sh -s "$FLYCO_SCENE"
  wait "$ue_pid"
'
