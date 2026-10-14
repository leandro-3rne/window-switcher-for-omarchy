#!/bin/bash
# Move every mapped window from the active regular workspace into the hidden
# Scratchpad without following any of them or revealing the special workspace.
set -euo pipefail

source_workspace=$(hyprctl -j activeworkspace | jq -r '.id // empty')
[[ $source_workspace =~ ^[1-9][0-9]*$ ]] || exit 0

clients=$(hyprctl -j clients)
addresses=$(jq -r --argjson workspace "$source_workspace" '
    [.[] | select(.workspace.id == $workspace and .mapped == true) | .address]
    | unique[]
' <<<"$clients")
[[ -n $addresses ]] || exit 0

script_dir=$(dirname -- "${BASH_SOURCE[0]}")
bash "$script_dir/unfullscreen-workspace.sh" "$source_workspace"
bash "$script_dir/unfullscreen-workspace.sh" "special:scratchpad"

lua_addresses=""
while IFS= read -r address; do
    [[ $address =~ ^0x[0-9a-fA-F]+$ ]] || continue
    lua_addresses+="\"$address\","
done <<<"$addresses"
[[ -n $lua_addresses ]] || exit 0

hyprctl eval "
    local addresses = {$lua_addresses}
    for _, address in ipairs(addresses) do
      local w = hl.get_window(\"address:\" .. address)
      if w and w.workspace and w.workspace.id == $source_workspace then
        hl.dispatch(hl.dsp.window.move({ window = w, workspace = \"special:scratchpad\", follow = false }))
        hl.exec_scheduled_prop_refresh_immediately()
      end
    end
"
