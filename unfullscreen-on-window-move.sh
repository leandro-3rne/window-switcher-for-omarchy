#!/bin/bash
# Safety net for windows moved into a workspace outside the custom helpers.
set -euo pipefail

address=${1:-}
[[ $address =~ ^0x[0-9a-fA-F]+$ ]] || exit 2
sleep 0.03
clients=$(hyprctl -j clients) || exit 0
location=$(jq -r --arg address "$address" '
    first(.[] | select(.address == $address and .mapped == true)) as $window |
    if $window == null then "" else [$window.workspace.name, $window.monitor] | @tsv end
' <<<"$clients")
[[ -n $location ]] || exit 0
read -r workspace_name monitor_id <<<"$location"
[[ $workspace_name =~ ^([1-9][0-9]*|special:scratchpad)$ && $monitor_id =~ ^[0-9]+$ ]] || exit 0

has_existing_fullscreen=$(jq -r --arg address "$address" \
    --arg workspace "$workspace_name" --argjson monitor "$monitor_id" '
    any(.[]; .address != $address and .mapped == true
      and .workspace.name == $workspace and .monitor == $monitor
      and (.fullscreen // 0) > 0)
' <<<"$clients")
[[ $has_existing_fullscreen == true ]] || exit 0

exec bash "$(dirname -- "${BASH_SOURCE[0]}")/unfullscreen-workspace.sh" "$workspace_name" "$monitor_id"
