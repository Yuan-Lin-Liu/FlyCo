#!/usr/bin/env zsh
set -e

SESSION_NAME="${SESSION_NAME:-ros_commands_refactor}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="${ROOT_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
CONDA_ENV="${CONDA_ENV:-}"
CONDA_ROOT="${CONDA_ROOT:-}"
ROS_SETUP="${ROS_SETUP:-}"
WORKSPACE_SETUP="${WORKSPACE_SETUP:-}"
MIN_HEIGHT="1.0"
START_RVIZ="false"
LAUNCH_PROMPT_UI="true"
CLUSTER_TOLERANCE="1.0"
CLUSTER_MIN_X=""
CLUSTER_MAX_X=""
CLUSTER_MIN_Y=""
CLUSTER_MAX_Y=""
CLUSTER_MIN_Z=""
CLUSTER_MAX_Z=""
CLUSTER_ALGORITHM=""
TARGET_REFINE_MODE=""
TRACKING_CONFIG_FILE=""
CLUSTER_CONFIG_FILE=""
USE_CONFIG_MIN_HEIGHT="false"
RECALL_THRESHOLD="0.9"
TEXT_PROMPT=""
EVF_TEXT_INIT_ENABLED="true"
EVF_ROOT=""
EVF_MODEL_VERSION=""
BAG_PATH=""
BAG_DIR="${BAG_DIR:-${HOME}/bag}"
BAG_START="0"
BAG_RATE="1.0"
USE_CLOCK="true"
NKSR_SCALE_LAUNCH_ARG="nksr_scale:=0.2"
KEEP_ROS_ENV="false"
DEBUG_DUMP_DIR=""
DEBUG_DUMP_ONCE="false"
RUNTIME_CONFIG_PATH=""
MESH_PRED_CKPT_PATH=""
INTRINSICS_MODE=""
SCENE=""

usage() {
  cat <<USAGE
Usage:
  run_percept.sh [SCENE] [options]

Options:
  SCENE                   Scene prompt preset (arc, bahai, buddha, castle, christ,
                          church, outpost, pagoda, pisa_cathedral, sacre_coeur,
                          sant, schloss, statue, temple, tower, or windmill).
  --scene SCENE           Set the scene explicitly.
  -d | -s | -l            Legacy flags; all use the unified min_height=1.0.
  --nb | --ns             Legacy flags; both use the unified nksr_scale=0.2.
  --rviz                  Launch RViz from perception_stack.launch.
  --no-ui                 Disable the prompt UI.
  --min-height V          Override min_height directly.
  --cluster-tolerance V   Override cluster_tolerance.
  --nksr-scale V          Override nksr_scale.
  --cluster-min-x V       Override cluster_min_x.
  --cluster-max-x V       Override cluster_max_x.
  --cluster-min-y V       Override cluster_min_y.
  --cluster-max-y V       Override cluster_max_y.
  --cluster-min-z V       Override cluster_min_z.
  --cluster-max-z V       Override cluster_max_z.
  --cluster-algorithm V   Override cluster algorithm.
  --target-refine-mode V  Override cluster target refine mode.
  --tracking-config-file PATH
                          Override sam_tracking tracking config.
  --cluster-config-file PATH
                          Override sam_tracking cluster config.
  --use-config-min-height Use min_height from config files instead of launch override.
  --recall-threshold V    Freeze mesh updates at this Flight Coverage fraction.
  --text-prompt TEXT      Publish text prompt to tracking and mesh_predict.
  --evf-text-init         Enable EVF text initialization (enabled by default).
  --no-evf-text-init      Disable EVF initialization; text still conditions mesh_predict.
  --evf-root PATH        Override the EVF-SAM source directory.
  --evf-model-version V  Override the EVF checkpoint path or model ID.
  --bag PATH|NAME         Play a rosbag in an extra pane. If not a file, resolve from BAG_DIR.
  --bag-dir PATH          Directory used to resolve bag names. Default: \$HOME/bag
  --start SECONDS         rosbag play --start value. Default: 0.
  --rate RATE             rosbag play -r value. Default: 1.0.
  --no-clock              Do not pass --clock to rosbag play.
  --debug-dump-dir PATH   Dump next mesh_predict pointcloud inference inputs/outputs.
  --debug-dump-once       Dump only the first successful pointcloud prediction.
  --runtime-config PATH   Override mesh_predict runtime config YAML.
  --mesh-ckpt PATH        Override mesh_predict checkpoint path.
  --intrinsics-mode MODE  Model K convention: camera_info or training_legacy.
  --keep-ros-env          Preserve caller ROS_MASTER_URI/ROS_IP/ROS_HOSTNAME.
  --session NAME          Override tmux session name.
  -h | --help             Show this help.

Examples:
  run_percept.sh church --rviz
  run_percept.sh pagoda --bag pagoda --start 10 --rate 1.0
  run_percept.sh sacre_coeur --no-ui --debug-dump-dir /tmp/sacre_coeur_dump
USAGE
}

if [[ $# -gt 0 && "$1" != -* ]]; then
  SCENE="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scene) SCENE="$2"; shift 2 ;;
    --scene=*) SCENE="${1#--scene=}"; shift ;;
    -d|-s|-l) MIN_HEIGHT="1.0"; shift ;;
    --nb|--ns) NKSR_SCALE_LAUNCH_ARG="nksr_scale:=0.2"; shift ;;
    --rviz) START_RVIZ="true"; shift ;;
    --no-ui) LAUNCH_PROMPT_UI="false"; shift ;;
    --min-height) MIN_HEIGHT="$2"; shift 2 ;;
    --cluster-tolerance) CLUSTER_TOLERANCE="$2"; shift 2 ;;
    --nksr-scale) NKSR_SCALE_LAUNCH_ARG="nksr_scale:=$2"; shift 2 ;;
    --cluster-min-x) CLUSTER_MIN_X="$2"; shift 2 ;;
    --cluster-max-x) CLUSTER_MAX_X="$2"; shift 2 ;;
    --cluster-min-y) CLUSTER_MIN_Y="$2"; shift 2 ;;
    --cluster-max-y) CLUSTER_MAX_Y="$2"; shift 2 ;;
    --cluster-min-z) CLUSTER_MIN_Z="$2"; shift 2 ;;
    --cluster-max-z) CLUSTER_MAX_Z="$2"; shift 2 ;;
    --cluster-algorithm) CLUSTER_ALGORITHM="$2"; shift 2 ;;
    --target-refine-mode) TARGET_REFINE_MODE="$2"; shift 2 ;;
    --tracking-config-file) TRACKING_CONFIG_FILE="$2"; shift 2 ;;
    --cluster-config-file) CLUSTER_CONFIG_FILE="$2"; shift 2 ;;
    --use-config-min-height) USE_CONFIG_MIN_HEIGHT="true"; shift ;;
    --recall-threshold) RECALL_THRESHOLD="$2"; shift 2 ;;
    --text-prompt) TEXT_PROMPT="$2"; shift 2 ;;
    --evf-text-init) EVF_TEXT_INIT_ENABLED="true"; shift ;;
    --no-evf-text-init) EVF_TEXT_INIT_ENABLED="false"; shift ;;
    --evf-root) EVF_ROOT="$2"; shift 2 ;;
    --evf-model-version) EVF_MODEL_VERSION="$2"; shift 2 ;;
    --bag-dir) BAG_DIR="$2"; shift 2 ;;
    --bag) BAG_PATH="$2"; shift 2 ;;
    --start|--bag-start) BAG_START="$2"; shift 2 ;;
    --rate|--bag-rate) BAG_RATE="$2"; shift 2 ;;
    --no-clock) USE_CLOCK="false"; shift ;;
    --debug-dump-dir) DEBUG_DUMP_DIR="$2"; shift 2 ;;
    --debug-dump-once) DEBUG_DUMP_ONCE="true"; shift ;;
    --runtime-config) RUNTIME_CONFIG_PATH="$2"; shift 2 ;;
    --mesh-ckpt) MESH_PRED_CKPT_PATH="$2"; shift 2 ;;
    --intrinsics-mode) INTRINSICS_MODE="$2"; shift 2 ;;
    --keep-ros-env) KEEP_ROS_ENV="true"; shift ;;
    --session) SESSION_NAME="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -n "$INTRINSICS_MODE" && "$INTRINSICS_MODE" != "camera_info" && "$INTRINSICS_MODE" != "training_legacy" ]]; then
  echo "Unknown intrinsics mode: $INTRINSICS_MODE" >&2
  exit 2
fi

SCENE_PROMPT=""
case "$SCENE" in
  "") ;;
  arc) SCENE_PROMPT="A small stone ornamental arch featuring a tiered roof and flared side wings." ;;
  bahai) SCENE_PROMPT="A large white domed temple with ribbed vertical facades and symmetrical side volumes." ;;
  buddha) SCENE_PROMPT="A seated Buddha statue on a circular terraced platform in a mountainous landscape." ;;
  castle) SCENE_PROMPT="A rectangular castle-like building with arched facades, corner turrets, and a flat roof." ;;
  christ) SCENE_PROMPT="A slender Christ-like statue with outstretched arms standing on a raised stone pedestal." ;;
  church) SCENE_PROMPT="A stone church with a long rectangular nave, steep roof, and a prominent square bell tower." ;;
  outpost) SCENE_PROMPT="A compact outpost building with a red gabled roof and a small tower-like front section." ;;
  pagoda) SCENE_PROMPT="A multi-tiered wooden pagoda with stacked curved eaves and a tapered vertical silhouette." ;;
  pisa_cathedral) SCENE_PROMPT="A large cathedral-like structure with a stepped roofline and elongated rectangular wings." ;;
  sacre_coeur) SCENE_PROMPT="An ornate cathedral with multiple domes, spires, and an irregular sculptural roofline." ;;
  sant) SCENE_PROMPT="A monument-like structure with a tall rectangular tower attached to a low curved base." ;;
  schloss) SCENE_PROMPT="A castle-like mansion with steep gabled roofs, elongated wings, and small tower-like corner structures." ;;
  statue) SCENE_PROMPT="A tall standing statue on a stepped pedestal, holding a torch aloft in its right hand." ;;
  temple) SCENE_PROMPT="A multi-tiered temple with stacked eaves and a pointed spire." ;;
  tower) SCENE_PROMPT="A colorful multi-story tower with stacked circular roofs and a slender spire." ;;
  windmill) SCENE_PROMPT="A compact red-and-white windmill with four cross-shaped blades and a narrow tapered tower." ;;
  *)
    echo "Unknown scene: $SCENE" >&2
    usage >&2
    exit 2
    ;;
esac
if [[ "$LAUNCH_PROMPT_UI" == "false" && -z "$TEXT_PROMPT" ]]; then
  TEXT_PROMPT="$SCENE_PROMPT"
fi
UI_TEXT_PROMPT="${TEXT_PROMPT:-$SCENE_PROMPT}"
if [[ -z "$ROS_SETUP" ]]; then
  if [[ -f "/opt/ros/noetic/setup.zsh" ]]; then
    ROS_SETUP="/opt/ros/noetic/setup.zsh"
  else
    ROS_SETUP="/opt/ros/noetic/setup.bash"
  fi
fi
if [[ ! -f "$ROS_SETUP" ]]; then
  echo "Missing ROS setup file: $ROS_SETUP" >&2
  exit 1
fi

if [[ -z "$WORKSPACE_SETUP" ]]; then
  if [[ -f "$ROOT_DIR/devel/setup.zsh" ]]; then
    WORKSPACE_SETUP="$ROOT_DIR/devel/setup.zsh"
  else
    WORKSPACE_SETUP="$ROOT_DIR/devel/setup.bash"
  fi
fi
if [[ ! -f "$WORKSPACE_SETUP" ]]; then
  echo "Missing $ROOT_DIR/devel/setup.zsh or setup.bash. Build the workspace first." >&2
  exit 1
fi

PYTHON_ENV_CMD=""
if [[ "$CONDA_ENV" != "system" ]]; then
  if [[ -z "$CONDA_ROOT" ]]; then
    for candidate in "$HOME/anaconda3" "$HOME/miniconda3" "/opt/conda"; do
      if [[ -f "$candidate/etc/profile.d/conda.sh" ]]; then
        CONDA_ROOT="$candidate"
        break
      fi
    done
  fi
  if [[ -z "$CONDA_ROOT" || ! -f "$CONDA_ROOT/etc/profile.d/conda.sh" ]]; then
    echo "Cannot find conda.sh. Set CONDA_ROOT to your conda installation." >&2
    exit 1
  fi

  source "$CONDA_ROOT/etc/profile.d/conda.sh"
  if [[ -z "$CONDA_ENV" ]]; then
    if conda env list | awk '{print $1}' | grep -qx "flyco"; then
      CONDA_ENV="flyco"
    elif conda env list | awk '{print $1}' | grep -qx "sam_tk"; then
      CONDA_ENV="sam_tk"
    else
      echo "Cannot find conda env flyco or sam_tk. Set CONDA_ENV explicitly." >&2
      exit 1
    fi
  fi
  PYTHON_ENV_CMD=" && source $CONDA_ROOT/etc/profile.d/conda.sh && conda activate $CONDA_ENV"
fi

yaml_escape_single_quotes() {
  printf "%s" "$1" | sed "s/'/''/g"
}

TEXT_PROMPT_YAML=""
if [[ -n "$TEXT_PROMPT" ]]; then
  TEXT_PROMPT_YAML="$(yaml_escape_single_quotes "$TEXT_PROMPT")"
fi

if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  echo "会话 $SESSION_NAME 已存在。请先关闭或使用它。"
  echo "Attach: tmux attach -t $SESSION_NAME"
  echo "Kill:   tmux kill-session -t $SESSION_NAME"
  exit 1
fi

ROS_ENV_CMD=""
if [[ "$KEEP_ROS_ENV" == "true" ]]; then
  if [[ -n "${ROS_MASTER_URI:-}" ]]; then
    ROS_ENV_CMD="$ROS_ENV_CMD && export ROS_MASTER_URI=$(printf '%q' "$ROS_MASTER_URI")"
  else
    ROS_ENV_CMD="$ROS_ENV_CMD && unset ROS_MASTER_URI"
  fi
  if [[ -n "${ROS_IP:-}" ]]; then
    ROS_ENV_CMD="$ROS_ENV_CMD && export ROS_IP=$(printf '%q' "$ROS_IP")"
  else
    ROS_ENV_CMD="$ROS_ENV_CMD && unset ROS_IP"
  fi
  if [[ -n "${ROS_HOSTNAME:-}" ]]; then
    ROS_ENV_CMD="$ROS_ENV_CMD && export ROS_HOSTNAME=$(printf '%q' "$ROS_HOSTNAME")"
  else
    ROS_ENV_CMD="$ROS_ENV_CMD && unset ROS_HOSTNAME"
  fi
else
  ROS_ENV_CMD="$ROS_ENV_CMD && unset ROS_MASTER_URI && unset ROS_IP && unset ROS_HOSTNAME"
fi

BASE_CMD="cd $ROOT_DIR && source $ROS_SETUP$PYTHON_ENV_CMD$ROS_ENV_CMD && export HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 && source $WORKSPACE_SETUP"
PERCEPTION_CMD="$BASE_CMD && roslaunch sam_tracking perception_stack.launch launch_prompt_ui:=$LAUNCH_PROMPT_UI"
if [[ "$LAUNCH_PROMPT_UI" == "true" && -n "$UI_TEXT_PROMPT" ]]; then
  PERCEPTION_CMD="$PERCEPTION_CMD ui_initial_text_prompt:=$(printf '%q' "$UI_TEXT_PROMPT")"
fi
if [[ "$START_RVIZ" == "true" ]]; then
  PERCEPTION_CMD="$PERCEPTION_CMD launch_rviz:=true"
fi
if [[ -n "$TEXT_PROMPT" ]]; then
  PERCEPTION_CMD="$PERCEPTION_CMD initial_text_prompt:=$(printf '%q' "$TEXT_PROMPT")"
fi
if [[ -n "$EVF_TEXT_INIT_ENABLED" ]]; then
  PERCEPTION_CMD="$PERCEPTION_CMD evf_text_init_enabled:=$EVF_TEXT_INIT_ENABLED"
fi
if [[ -n "$EVF_ROOT" ]]; then
  PERCEPTION_CMD="$PERCEPTION_CMD evf_root:=$(printf '%q' "$EVF_ROOT")"
fi
if [[ -n "$EVF_MODEL_VERSION" ]]; then
  PERCEPTION_CMD="$PERCEPTION_CMD evf_model_version:=$(printf '%q' "$EVF_MODEL_VERSION")"
fi
if [[ "$USE_CONFIG_MIN_HEIGHT" != "true" ]]; then
  PERCEPTION_CMD="$PERCEPTION_CMD min_height:=$MIN_HEIGHT"
else
  PERCEPTION_CMD="$PERCEPTION_CMD use_config_min_height:=true"
fi
if [[ -n "$TRACKING_CONFIG_FILE" ]]; then
  PERCEPTION_CMD="$PERCEPTION_CMD tracking_config_file:=$TRACKING_CONFIG_FILE"
fi
if [[ -n "$CLUSTER_CONFIG_FILE" ]]; then
  PERCEPTION_CMD="$PERCEPTION_CMD cluster_config_file:=$CLUSTER_CONFIG_FILE"
fi
if [[ -n "$CLUSTER_TOLERANCE" ]]; then
  PERCEPTION_CMD="$PERCEPTION_CMD cluster_tolerance:=$CLUSTER_TOLERANCE"
fi
if [[ -n "$CLUSTER_ALGORITHM" ]]; then
  PERCEPTION_CMD="$PERCEPTION_CMD cluster_algorithm:=$CLUSTER_ALGORITHM"
fi
if [[ -n "$TARGET_REFINE_MODE" ]]; then
  PERCEPTION_CMD="$PERCEPTION_CMD target_refine_mode:=$TARGET_REFINE_MODE"
fi
if [[ -n "$CLUSTER_MIN_X" ]]; then
  PERCEPTION_CMD="$PERCEPTION_CMD cluster_min_x:=$CLUSTER_MIN_X"
fi
if [[ -n "$CLUSTER_MAX_X" ]]; then
  PERCEPTION_CMD="$PERCEPTION_CMD cluster_max_x:=$CLUSTER_MAX_X"
fi
if [[ -n "$CLUSTER_MIN_Y" ]]; then
  PERCEPTION_CMD="$PERCEPTION_CMD cluster_min_y:=$CLUSTER_MIN_Y"
fi
if [[ -n "$CLUSTER_MAX_Y" ]]; then
  PERCEPTION_CMD="$PERCEPTION_CMD cluster_max_y:=$CLUSTER_MAX_Y"
fi
if [[ -n "$CLUSTER_MIN_Z" ]]; then
  PERCEPTION_CMD="$PERCEPTION_CMD cluster_min_z:=$CLUSTER_MIN_Z"
fi
if [[ -n "$CLUSTER_MAX_Z" ]]; then
  PERCEPTION_CMD="$PERCEPTION_CMD cluster_max_z:=$CLUSTER_MAX_Z"
fi
if [[ -n "$NKSR_SCALE_LAUNCH_ARG" ]]; then
  PERCEPTION_CMD="$PERCEPTION_CMD $NKSR_SCALE_LAUNCH_ARG"
fi
if [[ -n "$RECALL_THRESHOLD" ]]; then
  PERCEPTION_CMD="$PERCEPTION_CMD recall_threshold:=$RECALL_THRESHOLD"
fi
if [[ -n "$RUNTIME_CONFIG_PATH" ]]; then
  PERCEPTION_CMD="$PERCEPTION_CMD runtime_config_path:=$(printf '%q' "$RUNTIME_CONFIG_PATH")"
fi
if [[ -n "$MESH_PRED_CKPT_PATH" ]]; then
  PERCEPTION_CMD="$PERCEPTION_CMD mesh_pred_ckpt_path:=$(printf '%q' "$MESH_PRED_CKPT_PATH")"
fi
if [[ -n "$INTRINSICS_MODE" ]]; then
  PERCEPTION_CMD="$PERCEPTION_CMD intrinsics_mode:=$INTRINSICS_MODE"
fi
if [[ -n "$DEBUG_DUMP_DIR" ]]; then
  PERCEPTION_CMD="$PERCEPTION_CMD debug_dump_dir:=$(printf '%q' "$DEBUG_DUMP_DIR")"
fi
if [[ "$DEBUG_DUMP_ONCE" == "true" ]]; then
  PERCEPTION_CMD="$PERCEPTION_CMD debug_dump_once:=true"
fi
TEXT_PROMPT_PUBLISH_CMD=""
if [[ -n "$TEXT_PROMPT_YAML" ]]; then
  TEXT_PROMPT_PUBLISH_CMD="$BASE_CMD && sleep 5 && rostopic pub -1 /query_text std_msgs/String \"data: '$TEXT_PROMPT_YAML'\" && rostopic pub -1 /text_prompt std_msgs/String \"data: '$TEXT_PROMPT_YAML'\""
fi

EXTRA_CMD=""
if [[ -n "$BAG_PATH" ]]; then
  if [[ ! -f "$BAG_PATH" ]]; then
    if [[ -f "$BAG_DIR/$BAG_PATH" ]]; then
      BAG_PATH="$BAG_DIR/$BAG_PATH"
    elif [[ -f "$BAG_DIR/$BAG_PATH.bag" ]]; then
      BAG_PATH="$BAG_DIR/$BAG_PATH.bag"
    fi
  fi
  if [[ ! -f "$BAG_PATH" ]]; then
    echo "Bag not found: $BAG_PATH" >&2
    exit 1
  fi
  BAG_CMD="$BASE_CMD && sleep 5"
  if [[ -n "$TEXT_PROMPT_PUBLISH_CMD" ]]; then
    BAG_CMD="$BAG_CMD && rostopic pub -1 /query_text std_msgs/String \"data: '$TEXT_PROMPT_YAML'\" && rostopic pub -1 /text_prompt std_msgs/String \"data: '$TEXT_PROMPT_YAML'\" && sleep 1"
  fi
  BAG_CMD="$BAG_CMD && rosbag play $BAG_PATH --start $BAG_START -r $BAG_RATE"
  if [[ "$USE_CLOCK" == "true" ]]; then
    BAG_CMD="$BAG_CMD --clock"
  fi
  EXTRA_CMD="$BAG_CMD"
fi

# Keep the perception stack in one roslaunch process; optional tools get separate panes.
tmux new-session -d -s "$SESSION_NAME" -n "ROS"

send_zsh_command() {
  local target="$1"
  local command="$2"
  tmux send-keys -t "$target" "zsh -lc $(printf "%q" "$command")" C-m
}

add_command_pane() {
  local command="$1"
  local pane_id
  pane_id="$(tmux split-window -v -P -F '#{pane_id}' -t "$SESSION_NAME:0.0")"
  send_zsh_command "$pane_id" "$command"
}

send_zsh_command "$SESSION_NAME:0.0" "$PERCEPTION_CMD"
if [[ -n "$TEXT_PROMPT_PUBLISH_CMD" && -z "$BAG_PATH" ]]; then
  add_command_pane "$TEXT_PROMPT_PUBLISH_CMD"
fi
if [[ -n "$EXTRA_CMD" ]]; then
  add_command_pane "$EXTRA_CMD"
fi
tmux select-layout -t "$SESSION_NAME" tiled

if [[ "${NO_ATTACH:-0}" != "1" && -t 1 ]]; then
  tmux attach-session -t "$SESSION_NAME"
else
  echo "No interactive TTY detected; session left running."
  echo "Attach with: tmux attach-session -t $SESSION_NAME"
fi

echo "所有命令已经在 tmux 中启动。"
echo "SESSION_NAME: $SESSION_NAME"
echo "min_height: $MIN_HEIGHT"
echo "cluster_tolerance: $CLUSTER_TOLERANCE"
echo "evf_text_init_enabled: $EVF_TEXT_INIT_ENABLED"
if [[ -n "$NKSR_SCALE_LAUNCH_ARG" ]]; then
  echo "NKSR_SCALE 参数: $NKSR_SCALE_LAUNCH_ARG"
fi
if [[ -n "$TEXT_PROMPT" ]]; then
  echo "text_prompt: $TEXT_PROMPT"
fi
if [[ -n "$BAG_PATH" ]]; then
  echo "bag: $BAG_PATH"
fi
if [[ -n "$DEBUG_DUMP_DIR" ]]; then
  echo "debug_dump_dir: $DEBUG_DUMP_DIR"
  echo "debug_dump_once: $DEBUG_DUMP_ONCE"
fi
if [[ -n "$RUNTIME_CONFIG_PATH" ]]; then
  echo "runtime_config_path: $RUNTIME_CONFIG_PATH"
fi
if [[ -n "$MESH_PRED_CKPT_PATH" ]]; then
  echo "mesh_pred_ckpt_path: $MESH_PRED_CKPT_PATH"
fi
