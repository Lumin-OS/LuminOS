#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# CI-only: installed into a copied profile, never the production ISO.
set -euo pipefail
for ((attempt=0; attempt<120; attempt++)); do
    for socket in /run/user/1000/hypr/*/.socket.sock; do
        [[ -S "$socket" ]] || continue
        instance=$(basename "$(dirname "$socket")")
        clients=$(runuser -u luminos -- env XDG_RUNTIME_DIR=/run/user/1000 \
            hyprctl -i "$instance" -j clients 2>/dev/null) || continue
        if jq -e 'any(.[]; .class == "luminos-dawn" and .mapped == true and .size[0] > 0)' \
            <<< "$clients" >/dev/null; then
            echo "LUMINOS-M5: Dawn window is mapped in Hyprland"
            systemctl poweroff
            exit 0
        fi
    done
    sleep 2
done
echo "LUMINOS-M5: Dawn did not appear" >&2
journalctl -b --no-pager -n 200
systemctl poweroff
exit 1
