#!/usr/bin/env bash
#
# Parse the vendored Hyprland config with the exact Hyprland version the image
# ships, and fail on any config error.
#
#   ./scripts/verify-session-config.sh
#
# Why this exists: the first candidate ISO booted to a working session that was
# also displaying a red box of ten config errors, because Hyprland 0.56 renamed
# options the 2024-era config used (`dwindle:pseudotile`, the `gestures{}`
# block, the `togglesplit` dispatcher, `windowrulev2`). Finding that took a full
# build-and-boot cycle. `Hyprland --verify-config` finds the same thing in
# seconds, so there is no reason to spend a 30-minute build on it.
#
# Run this after any change to the session config, before building.

set -euo pipefail

cd -- "$(dirname -- "$(readlink -f -- "$0")")/.."
# shellcheck source=../pin.env
source ./pin.env

CFG_DIR="releng/airootfs/home/luminos/.config"
[[ -f "$CFG_DIR/hypr/hyprland.conf" ]] || {
    echo "ERROR: no $CFG_DIR/hypr/hyprland.conf — run ./scripts/sync-dotfiles.sh first" >&2
    exit 1
}

ENGINE="${CONTAINER_ENGINE:-}"
if [[ -z $ENGINE ]]; then
    if command -v podman >/dev/null 2>&1; then ENGINE=podman
    elif command -v docker >/dev/null 2>&1; then ENGINE=docker
    else echo "need podman or docker" >&2; exit 1; fi
fi

echo "Verifying session config against the pinned snapshot ($ARCH_SNAPSHOT)"

"$ENGINE" run --rm \
    -e "ARCH_SNAPSHOT=$ARCH_SNAPSHOT" \
    -v "$PWD/$CFG_DIR:/cfg:ro" \
    "$BUILDER_IMAGE" \
    bash -euo pipefail -c '
        printf "Server = https://archive.archlinux.org/repos/%s/\$repo/os/\$arch\n" "$ARCH_SNAPSHOT" \
            > /etc/pacman.d/mirrorlist
        sed -i "s/^ParallelDownloads.*/ParallelDownloads = 1/" /etc/pacman.conf
        pacman -Syuu --noconfirm --needed >/dev/null 2>&1
        pacman -S --noconfirm --needed hyprland >/dev/null 2>&1

        echo "hyprland: $(pacman -Q hyprland | cut -d" " -f2)"

        # Hyprland refuses to run as root, and needs an XDG_RUNTIME_DIR even
        # just to parse a config.
        useradd -m -u 1000 luminos 2>/dev/null || true
        mkdir -p /home/luminos/.config /run/xdg-1000
        cp -r /cfg/. /home/luminos/.config/
        chown -R luminos:luminos /home/luminos /run/xdg-1000

        out=$(su luminos -c "XDG_RUNTIME_DIR=/run/xdg-1000 Hyprland --verify-config" 2>&1)
        echo "$out" | sed -n "/Config parsing result/,\$p"

        if echo "$out" | grep -q "^Config error"; then
            echo
            echo "FAILED: the session would boot showing a config-error banner."
            exit 1
        fi
    '

echo
echo "OK: session config parses clean"
