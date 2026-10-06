#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 gdown-files.json destination-directory" >&2
  exit 2
fi

download_one() {
  local url="$1" relative="$2" id target temporary magic
  id="${url##*=}"
  [[ "$id" =~ ^[A-Za-z0-9_-]+$ && "$relative" != /* && "$relative" != ../* && "$relative" != */../* ]] || return 1
  target="$ASSET_ROOT/$relative"
  if [[ -s "$target" ]]; then
    if [[ "$target" != *.uasset && "$target" != *.umap ]]; then
      return 0
    fi
    [[ "$(od -An -tx1 -N4 "$target" | tr -d ' \n')" == c1832a9e ]] && return 0
  fi
  mkdir -p "$(dirname "$target")"
  temporary="$target.part"
  curl -fsSL --retry 3 --connect-timeout 20 --max-time 1200 \
    -o "$temporary" "https://drive.usercontent.google.com/download?id=$id&export=download"
  if [[ "$target" == *.uasset || "$target" == *.umap ]]; then
    magic="$(od -An -tx1 -N4 "$temporary" | tr -d ' \n')"
    [[ "$magic" == c1832a9e ]] || { echo "Invalid UE asset: $relative" >&2; return 1; }
  fi
  mv "$temporary" "$target"
  printf '%s\n' "$relative"
}

export ASSET_ROOT="$2"
export -f download_one
python3 - "$1" <<'PY' | \
  xargs -0 -n 2 -P "${DOWNLOAD_JOBS:-6}" bash -c 'download_one "$1" "$2"' _
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    for item in json.load(source):
        sys.stdout.buffer.write(item["url"].encode() + b"\0" + item["path"].encode() + b"\0")
PY
