#!/bin/bash
set -euo pipefail

command=${1:?Usage: unfullscreen-before-launch.sh 'command'|--prepare-only}
script_dir=$(dirname -- "${BASH_SOURCE[0]}")
active_workspace=$(hyprctl -j activeworkspace 2>/dev/null | jq -r '.id // empty' 2>/dev/null || true)
active_window=$(hyprctl -j activewindow 2>/dev/null || true)
active_workspace_name=$(jq -r '.workspace.name // ""' <<<"$active_window" 2>/dev/null || true)

if [[ $active_workspace_name == "special:scratchpad" ]]; then
  monitor_id=$(jq -r '.monitor // empty' <<<"$active_window" 2>/dev/null || true)
  if [[ $monitor_id =~ ^[0-9]+$ ]]; then
    bash "$script_dir/unfullscreen-workspace.sh" "special:scratchpad" "$monitor_id" || true
  fi
  sleep 0.01
elif [[ $active_workspace =~ ^[1-9][0-9]*$ ]]; then
  bash "$script_dir/unfullscreen-workspace.sh" "$active_workspace" || true
else
  fullscreen_address=$(jq -r 'select((.fullscreen // 0) > 0) | .address // empty' <<<"$active_window")
  if [[ $fullscreen_address =~ ^0x[0-9a-fA-F]+$ ]]; then
    hyprctl eval "local w = hl.get_window(\"address:$fullscreen_address\"); if w then hl.dispatch(hl.dsp.window.fullscreen({ window = w, mode = \"fullscreen\" })) end" || true
  fi
fi

if [[ $active_workspace =~ ^[1-9][0-9]*$ ]]; then
  sleep 0.01
fi

[[ $command == --prepare-only ]] && exit 0
exec bash -lc "$command"
