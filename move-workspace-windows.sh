#!/bin/bash
# Move every mapped window from the active workspace to the numbered target.
set -euo pipefail

target_workspace=${1:-}
[[ $target_workspace =~ ^([1-9]|10)$ ]] || exit 2

active_window=$(hyprctl -j activewindow)
active_workspace_name=$(jq -r '.workspace.name // ""' <<<"$active_window")
if [[ $active_workspace_name == "special:scratchpad" ]]; then
    clients=$(hyprctl -j clients)
    addresses=$(jq -r '
        [.[] | select(.workspace.name == "special:scratchpad" and .mapped == true) | .address]
        | unique[]
    ' <<<"$clients")
    [[ -n $addresses ]] || exit 0

    bash "$(dirname -- "${BASH_SOURCE[0]}")/unfullscreen-workspace.sh" "$target_workspace"
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
          if w and w.workspace and w.workspace.name == \"special:scratchpad\" then
            if (w.fullscreen or 0) > 0 then
              hl.dispatch(hl.dsp.window.fullscreen({ window = w, mode = \"fullscreen\", action = \"unset\" }))
            end
            hl.dispatch(hl.dsp.window.move({ window = w, workspace = \"$target_workspace\", follow = false }))
            hl.exec_scheduled_prop_refresh_immediately()
          end
        end
        hl.dispatch(hl.dsp.workspace.toggle_special(\"scratchpad\"))
        hl.dispatch(hl.dsp.focus({ workspace = \"$target_workspace\" }))
    "
    exit 0
fi

source_workspace=$(hyprctl -j activeworkspace | jq -r '.id // empty')
[[ $source_workspace =~ ^[1-9][0-9]*$ ]] || exit 0
[[ $source_workspace != "$target_workspace" ]] || exit 0

clients=$(hyprctl -j clients)
workspaces=$(hyprctl -j workspaces)
workspace_rules=$(hyprctl -j workspacerules)
addresses=$(jq -r --argjson workspace "$source_workspace" '
    [.[] | select(.workspace.id == $workspace and .mapped == true) | .address]
    | unique[]
' <<<"$clients")
[[ -n $addresses ]] || exit 0

active_workspace=$(hyprctl -j activeworkspace)
source_monitor=$(jq -r '.monitor // ""' <<<"$active_workspace")
target_info=$(jq -c --argjson workspace "$target_workspace" '
    first(.[] | select(.id == $workspace)) // empty
' <<<"$workspaces")
target_monitor=""
target_windows=0
if [[ -n $target_info ]]; then
    target_monitor=$(jq -r '.monitor // ""' <<<"$target_info")
    target_windows=$(jq -r '.windows // 0' <<<"$target_info")
else
    target_monitor=$(jq -r --arg workspace "$target_workspace" '
        first(.[] | select(.workspaceString == $workspace)) | .monitor // ""
    ' <<<"$workspace_rules")
fi

# Clear fullscreen on the destination before dispatching any workspace moves,
# and on the source so a fullscreen window cannot carry over into the merge.
helper="$(dirname -- "${BASH_SOURCE[0]}")/unfullscreen-workspace.sh"
bash "$helper" "$target_workspace"
bash "$helper" "$source_workspace"

# With an empty destination, changing the workspace IDs moves the existing
# workspace object and its complete tiling tree instead of re-tiling windows
# one at a time. If the empty target already exists, temporarily exchange IDs.
if [[ -n $target_info && $target_windows -eq 0 ]]; then
    temporary_workspace=11
    while jq -e --argjson id "$temporary_workspace" 'any(.[]; .id == $id)' <<<"$workspaces" >/dev/null \
        || jq -e --arg id "$temporary_workspace" 'any(.[]; .workspaceString == $id)' <<<"$workspace_rules" >/dev/null; do
        temporary_workspace=$((temporary_workspace + 1))
    done

    hyprctl eval "
        if \"$target_monitor\" ~= \"$source_monitor\" then
          -- Put the empty numbered workspace on its monitor first, then swap
          -- whole active workspaces. This avoids both monitors exposing a
          -- neighboring fallback while preserving the source tiling tree.
          hl.dispatch(hl.dsp.focus({ workspace = \"$target_workspace\" }))
          hl.dispatch(hl.dsp.workspace.swap_monitors({ monitor1 = \"$source_monitor\", monitor2 = \"$target_monitor\" }))
        end
        hl.dispatch(hl.dsp.workspace.change_id({ workspace = \"$target_workspace\", id = $temporary_workspace }))
        hl.dispatch(hl.dsp.workspace.change_id({ workspace = \"$source_workspace\", id = $target_workspace }))
        hl.dispatch(hl.dsp.workspace.change_id({ workspace = \"$temporary_workspace\", id = $source_workspace }))
        hl.exec_scheduled_prop_refresh_immediately()
        hl.dispatch(hl.dsp.focus({ workspace = \"$target_workspace\" }))
    "
    exit 0
fi

# If the numbered workspace has not been created yet, reassign this workspace
# directly. A workspace rule can still place it on its configured monitor.
if [[ -z $target_info ]]; then
    hyprctl eval "
        hl.dispatch(hl.dsp.workspace.change_id({ workspace = \"$source_workspace\", id = $target_workspace }))
        if \"$target_monitor\" ~= \"\" and \"$target_monitor\" ~= \"$source_monitor\" then
          -- Reserve the old monitor's source id before moving the whole
          -- workspace away, so it does not advance to a neighboring id.
          hl.dispatch(hl.dsp.focus({ workspace = \"$source_workspace\" }))
          hl.dispatch(hl.dsp.workspace.move({ workspace = \"$target_workspace\", monitor = \"$target_monitor\" }))
        end
        hl.exec_scheduled_prop_refresh_immediately()
        hl.dispatch(hl.dsp.focus({ workspace = \"$target_workspace\" }))
    "
    exit 0
fi

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
        hl.dispatch(hl.dsp.window.move({ window = w, workspace = \"$target_workspace\", follow = false }))
        hl.exec_scheduled_prop_refresh_immediately()
      end
    end
    hl.dispatch(hl.dsp.focus({ workspace = \"$target_workspace\" }))
"
