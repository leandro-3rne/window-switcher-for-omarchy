#!/bin/bash
# When a second client opens on a fullscreen workspace/output, clear
# fullscreen from every fullscreen client there.
set -euo pipefail

new_address=${1:-}
[[ $new_address =~ ^0x[0-9a-fA-F]+$ ]] || exit 2
clients_at_open=$(hyprctl -j clients)
fullscreen_at_open=$(jq -c --arg address "$new_address" '
  [.[] | select(.address != $address and .mapped == true
    and (.workspace.name // "") != "" and (.fullscreen // 0) > 0)
   | {address, monitor, workspaceId: .workspace.id, workspaceName: .workspace.name}]
' <<<"$clients_at_open")
[[ $(jq 'length' <<<"$fullscreen_at_open") -gt 0 ]] || exit 0

addresses=""
for attempt in {1..25}; do
  sleep 0.12
  clients=$(hyprctl -j clients)
  # Only clear fullscreen windows that were already fullscreen when this
  # openwindow event arrived. A later Super+F must not be mistaken for that state.
  state=$(jq -c --arg address "$new_address" --argjson initial "$fullscreen_at_open" '
    (first(.[] | select(.address == $address)) // null) as $new |
     if $new == null or ($new.workspace.name // "") == "" then empty
     else
       [.[] | select(.mapped == true and .monitor == $new.monitor
         and .workspace.id == $new.workspace.id
         and .workspace.name == $new.workspace.name)] as $windows |
       [$initial[] | select(.monitor == $new.monitor
         and .workspaceId == $new.workspace.id
         and .workspaceName == $new.workspace.name)] as $full |
      [$windows[] | select((.fullscreen // 0) > 0)] as $currently_full |
      {popup: ($new.floating // false),
       ready: (($windows | length) >= 2),
       addresses: (if ($windows | length) >= 2 and ($full | length) > 0
          then [$currently_full[].address] else [] end)}
    end
  ' <<<"$clients")
  [[ -n $state ]] || continue
  popup=$(jq -r '.popup' <<<"$state")
  [[ $popup == true ]] && exit 0
  ready=$(jq -r '.ready' <<<"$state")
  addresses=$(jq -r '.addresses[]?' <<<"$state")
  [[ -n $addresses ]] && break
  [[ $ready == true ]] && exit 0
done
[[ -n $addresses ]] || exit 0

# This event arrives after mapping, so the launch wrapper handles the desired
# pre-launch ordering. Keep this short delay only for launches outside wrappers.
sleep 0.12

lua="local addresses = {"
while IFS= read -r address; do
  [[ $address =~ ^0x[0-9a-fA-F]+$ ]] || continue
  lua+="\"$address\","
done <<<"$addresses"
lua+="}; for _, address in ipairs(addresses) do local w = hl.get_window(\"address:\" .. address); if w then hl.dispatch(hl.dsp.window.fullscreen({ window = w, mode = \"fullscreen\", action = \"unset\" })) end end; hl.exec_scheduled_prop_refresh_immediately()"
hyprctl eval "$lua"
