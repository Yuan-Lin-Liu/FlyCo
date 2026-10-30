#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
  echo "Usage: bash docker/keyboard.sh [scene] [--check]"
  echo "Connect a keyboard to an already running FlyCo scene (default: bahai)."
  exit 0
fi
scene="${1:-bahai}"
[[ "$scene" =~ ^[a-z0-9_]+$ && $# -le 2 ]] || { echo "Usage: bash docker/keyboard.sh [scene] [--check]" >&2; exit 2; }
[[ $# -lt 2 || "$2" == --check ]] || { echo "Unknown option: $2" >&2; exit 2; }
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
container="flyco-$scene"
[[ "$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null)" == true ]] || {
  echo "Start the scene first: ./docker/run.sh $scene" >&2
  exit 1
}
args=(-i)
if [[ "${2:-}" != --check ]]; then
  [[ -t 0 && -t 1 ]] || { echo "Run this command in an interactive terminal." >&2; exit 1; }
  args+=(-t)
fi
# Copy into the running container so an image rebuild/restart is unnecessary.
docker cp "$here/keyboard-control.py" "$container:/tmp/flyco-keyboard.py"
exec docker exec "${args[@]}" -e DISABLE_ROS1_EOL_WARNINGS=1 "$container" \
  bash -lc 'source /opt/flyco/perception_predictor/devel/setup.bash && exec python3 /tmp/flyco-keyboard.py "$@"' \
  flyco-keyboard "${@:2}"
