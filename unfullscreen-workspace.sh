#!/bin/bash
# Remove fullscreen from windows already on a workspace before another window
# is shown or moved into it.
set -euo pipefail

workspace_id=${1:-}
monitor_id=${2:-}
[[ $workspace_id =~ ^[1-9][0-9]*$ || $workspace_id == "special:scratchpad" ]] || exit 0
if [[ -n $monitor_id && ! $monitor_id =~ ^[0-9]+$ ]]; then exit 2; fi

clients=$(hyprctl -j clients)
if [[ -n $monitor_id ]]; then
    fullscreen_addresses=$(jq -r --arg workspace "$workspace_id" --argjson monitor "$monitor_id" '
        [.[] | select((if $workspace == "special:scratchpad" then .workspace.name == $workspace
          else .workspace.id == ($workspace | tonumber) end) and .monitor == $monitor
          and .mapped == true and (.fullscreen // 0) > 0) | .address] | unique[]
    ' <<<"$clients")
else
    fullscreen_addresses=$(jq -r --arg workspace "$workspace_id" '
        [.[] | select((if $workspace == "special:scratchpad" then .workspace.name == $workspace
          else .workspace.id == ($workspace | tonumber) end)
          and .mapped == true and (.fullscreen // 0) > 0) | .address] | unique[]
    ' <<<"$clients")
fi
[[ -n $fullscreen_addresses ]] || exit 0

lua_addresses=""
while IFS= read -r address; do
    [[ $address =~ ^0x[0-9a-fA-F]+$ ]] || continue
    lua_addresses+="\"$address\","
done <<<"$fullscreen_addresses"
[[ -n $lua_addresses ]] || exit 0

hyprctl eval "
    local addresses = {$lua_addresses}
    for _, address in ipairs(addresses) do
      local w = hl.get_window(\"address:\" .. address)
      if w then hl.dispatch(hl.dsp.window.fullscreen({ window = w, mode = \"fullscreen\", action = \"unset\" })) end
    end
    hl.exec_scheduled_prop_refresh_immediately()
"
