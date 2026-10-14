#!/bin/bash
# Swap with an adjacent window on this output first. The cross-monitor exchange
# handles fullscreen windows; moving a window to another monitor has a separate
# shortcut. A fullscreen exchange exits fullscreen on both windows first.
set -euo pipefail

direction=${1:-}
[[ $direction =~ ^[lrud]$ ]] || exit 2
active=$(hyprctl -j activewindow)
clients=$(hyprctl -j clients)
monitors=$(hyprctl -j monitors)
active_address=$(jq -r '.address // ""' <<<"$active")

read -r same_target active_fullscreen same_fullscreen < <(
  jq -nr --arg dir "$direction" --argjson active "$active" --argjson clients "$clients" '
    ($active.at[0] + $active.size[0] / 2) as $cx |
    ($active.at[1] + $active.size[1] / 2) as $cy |
    ([$clients[] | select(.address != $active.address and .mapped == true
      and .hidden != true
      and (.visible == true or (($active.fullscreen // 0) > 0 and ((.grouped // []) | length) == 0))
      and .monitor == $active.monitor and .workspace.id == $active.workspace.id) |
      . as $w | ($w.at[0] + $w.size[0] / 2 - $cx) as $dx |
      ($w.at[1] + $w.size[1] / 2 - $cy) as $dy |
      select(if $dir == "l" then $dx < 0 elif $dir == "r" then $dx > 0
        elif $dir == "u" then $dy < 0 else $dy > 0 end) |
      . + {primary: (if $dir == "l" or $dir == "r" then ($dx|fabs) else ($dy|fabs) end),
           secondary: (if $dir == "l" or $dir == "r" then ($dy|fabs) else ($dx|fabs) end)}]
      | sort_by(.primary, .secondary) | .[0]) as $target |
    [($target.address // ""), ($active.fullscreen // 0), ($target.fullscreen // 0)] | @tsv
  '
)
active_fullscreen=$(jq -r '.fullscreen // 0' <<<"$active")

if [[ $same_target =~ ^0x[0-9a-fA-F]+$ ]]; then
  if (( active_fullscreen > 0 || same_fullscreen > 0 )); then
    hyprctl eval "
      local a = hl.get_window(\"address:$active_address\")
      local b = hl.get_window(\"address:$same_target\")
      if a and $active_fullscreen > 0 then hl.dispatch(hl.dsp.window.fullscreen({ window = a, mode = \"fullscreen\" })) end
      if b and $same_fullscreen > 0 then hl.dispatch(hl.dsp.window.fullscreen({ window = b, mode = \"fullscreen\" })) end
      hl.exec_scheduled_prop_refresh_immediately()
      hl.dispatch(hl.dsp.window.swap({ direction = \"$direction\" }))
    "
  else
    hyprctl eval "hl.dispatch(hl.dsp.window.swap({ direction = \"$direction\" }))"
  fi
  exit 0
fi

# Consider a cross-monitor exchange only when one of its windows is fullscreen.
read -r source target source_ws target_ws source_fs target_fs < <(
    jq -nr --arg dir "$direction" --argjson active "$active" \
      --argjson clients "$clients" --argjson monitors "$monitors" '
      (first($monitors[] | select(.id == $active.monitor)) // null) as $origin |
      ($origin.x + $origin.width / 2) as $cx |
      ($origin.y + $origin.height / 2) as $cy |
      ([$monitors[] | select(.id != $active.monitor) |
        . as $m | (.x + .width / 2 - $cx) as $dx |
        (.y + .height / 2 - $cy) as $dy |
        select(if $dir == "l" then $dx < 0 elif $dir == "r" then $dx > 0
          elif $dir == "u" then $dy < 0 else $dy > 0 end) |
        . + {distance: ($dx * $dx + $dy * $dy)}]
        | sort_by(.distance) | .[0]) as $other |
       ([$clients[] | select($other != null and .monitor == $other.id
         and .workspace.id == $other.activeWorkspace.id and .mapped == true
         and .hidden != true and .visible == true)]
        | sort_by(-(.fullscreen // 0), (.focusHistoryID // 999999)) | .[0]) as $dest |
      if $origin == null or $dest == null or ($active.workspace.id // 0) <= 0
        or $origin.activeWorkspace.id != $active.workspace.id
        or (($active.fullscreen // 0) == 0 and ($dest.fullscreen // 0) == 0)
      then "" else [$active.address, $dest.address, $active.workspace.id,
        $dest.workspace.id, ($active.fullscreen // 0), ($dest.fullscreen // 0)] | @tsv end
    '
)

if [[ ! $source =~ ^0x[0-9a-fA-F]+$ ]]; then
    # No cross-monitor window either, fall back to native swap
    hyprctl eval "hl.dispatch(hl.dsp.window.swap({ direction = \"$direction\" }))"
    exit 0
fi

hyprctl eval "
    local a = hl.get_window(\"address:$source\")
    local b = hl.get_window(\"address:$target\")
    if a and a.group then hl.dispatch(hl.dsp.window.move({ window = a, out_of_group = true })) end
    if b and b.group then hl.dispatch(hl.dsp.window.move({ window = b, out_of_group = true })) end
    -- Exit fullscreen on both windows before swapping
    if ($source_fs > 0 or $target_fs > 0) then
      if $source_fs > 0 then hl.dispatch(hl.dsp.window.fullscreen({ window = a, mode = \"fullscreen\" })) end
      if $target_fs > 0 then hl.dispatch(hl.dsp.window.fullscreen({ window = b, mode = \"fullscreen\" })) end
      hl.exec_scheduled_prop_refresh_immediately()
    end
  "
hyprctl eval "
    local a = hl.get_window(\"address:$source\")
    local b = hl.get_window(\"address:$target\")
    if not a or not b then return end
    hl.exec_scheduled_prop_refresh_immediately()
    hl.dispatch(hl.dsp.window.move({ window = b, workspace = \"$source_ws\", follow = false }))
    hl.dispatch(hl.dsp.window.move({ window = a, workspace = \"$target_ws\", follow = false }))
    hl.exec_scheduled_prop_refresh_immediately()
    hl.dispatch(hl.dsp.focus({ window = a }))
  "
clients_after_swap=$(hyprctl -j clients)
cursor_position=$(jq -nr --arg address "$source" --argjson clients "$clients_after_swap" '
    first($clients[] | select(.address == $address)
      | [(.at[0] + .size[0] / 2 | floor), (.at[1] + .size[1] / 2 | floor)] | @tsv) // ""
')
if [[ $cursor_position =~ ^-?[0-9]+[[:blank:]]+-?[0-9]+$ ]]; then
    read -r cursor_x cursor_y <<<"$cursor_position"
    hyprctl eval "hl.dispatch(hl.dsp.cursor.move({ x = $cursor_x, y = $cursor_y }))"
fi
