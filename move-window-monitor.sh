#!/bin/bash
# Move only the active window to the nearest monitor in the requested direction.
set -euo pipefail

direction=${1:-}
[[ $direction =~ ^[lrud]$ ]] || exit 2
active=$(hyprctl -j activewindow)
monitors=$(hyprctl -j monitors)
active_address=$(jq -r '.address // ""' <<<"$active")
active_fullscreen=$(jq -r '.fullscreen // 0' <<<"$active")
is_scratchpad=$(jq -r '.workspace.name == "special:scratchpad"' <<<"$active")
scratchpad_window_count=0
if [[ $is_scratchpad == true ]]; then
  scratchpad_window_count=$(hyprctl -j clients | jq '[.[] | select(.workspace.name == "special:scratchpad" and .mapped == true)] | length')
fi

target_info=$(jq -nr --arg dir "$direction" --argjson active "$active" \
  --argjson monitors "$monitors" '
  (first($monitors[] | select(.id == $active.monitor)) // null) as $origin |
  ($origin.x + $origin.width / 2) as $cx |
  ($origin.y + $origin.height / 2) as $cy |
  ([$monitors[] | select(.id != $active.monitor) |
    (.x + .width / 2 - $cx) as $dx |
    (.y + .height / 2 - $cy) as $dy |
    select(if $dir == "l" then $dx < 0 elif $dir == "r" then $dx > 0
      elif $dir == "u" then $dy < 0 else $dy > 0 end) |
    . + {distance: ($dx * $dx + $dy * $dy)}]
    | sort_by(.distance) | .[0]) as $other |
  ($active.workspace.name == "special:scratchpad") as $scratchpad |
  if $origin == null or $other == null
    or (if $scratchpad then ($origin.activeWorkspace.id // 0) <= 0
        else ($active.workspace.id // 0) <= 0 or $origin.activeWorkspace.id != $active.workspace.id end)
    or ($other.activeWorkspace.id // 0) <= 0
  then "" else
    [(if $scratchpad then ($other.activeWorkspace.id | tostring)
      elif $other.specialWorkspace.name == "special:scratchpad" then "special:scratchpad"
      else ($other.activeWorkspace.id | tostring) end), ($other.id | tostring)] | @tsv
  end
')

[[ -n $target_info ]] || exit 0
read -r target_workspace target_monitor_id <<<"$target_info"
[[ $target_workspace =~ ^([1-9][0-9]*|special:scratchpad)$ && $target_monitor_id =~ ^[0-9]+$ ]] || exit 0
bash "$(dirname -- "${BASH_SOURCE[0]}")/unfullscreen-workspace.sh" "$target_workspace" "$target_monitor_id"

hyprctl eval "
    local a = hl.get_window(\"address:$active_address\")
    if not a then return end
    if a.group then
      hl.dispatch(hl.dsp.window.move({ window = a, out_of_group = true }))
      hl.exec_scheduled_prop_refresh_immediately()
      a = hl.get_window(\"address:$active_address\")
      if not a then return end
    end
    if $is_scratchpad and $active_fullscreen > 0 then
      hl.dispatch(hl.dsp.window.fullscreen({ window = a, mode = \"fullscreen\", action = \"unset\" }))
      hl.exec_scheduled_prop_refresh_immediately()
      a = hl.get_window(\"address:$active_address\")
      if not a then return end
    elseif $active_fullscreen > 0 then
      hl.dispatch(hl.dsp.window.fullscreen({ window = a, mode = \"fullscreen\" }))
      hl.exec_scheduled_prop_refresh_immediately()
      a = hl.get_window(\"address:$active_address\")
      if not a then return end
    end
    hl.dispatch(hl.dsp.window.move({ window = a, workspace = \"$target_workspace\", follow = true }))
    hl.exec_scheduled_prop_refresh_immediately()
    if $is_scratchpad and $scratchpad_window_count == 1 then
      hl.dispatch(hl.dsp.workspace.toggle_special(\"scratchpad\"))
    end
"

clients_after_move=$(hyprctl -j clients)
cursor_position=$(jq -nr --arg address "$active_address" --argjson clients "$clients_after_move" '
    first($clients[] | select(.address == $address)
      | [(.at[0] + .size[0] / 2 | floor), (.at[1] + .size[1] / 2 | floor)] | @tsv) // ""
')
if [[ $cursor_position =~ ^-?[0-9]+[[:blank:]]+-?[0-9]+$ ]]; then
    read -r cursor_x cursor_y <<<"$cursor_position"
    hyprctl eval "hl.dispatch(hl.dsp.cursor.move({ x = $cursor_x, y = $cursor_y }))"
fi
