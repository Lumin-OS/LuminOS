#!/usr/bin/env bash
#
# LuminOS ISO build — single entry point.
#
#   ./build.sh
#
# That is the whole command. It works from a clean checkout, needs no state from
# a previous run, and does not require archiso (or root) on the host.
#
# The build runs inside a pinned archlinux container for two reasons:
#   1. mkarchiso needs root plus a real Arch pacman/keyring. The founder's
#      machine is CachyOS, whose pacman.conf carries cachyos*/znver4 repos that
#      would leak non-Arch packages into the image.
#   2. Pinning the container to an Arch Linux Archive snapshot (see pin.env)
#      pins the build toolchain AND the image contents to one frozen date, which
#      is what makes the ISO reproducible next week instead of only today.
#
# Everything version-bearing lives in pin.env. This script contains no versions.

set -euo pipefail

readonly PROFILE="releng"
cd -- "$(dirname -- "$(readlink -f -- "$0")")"
readonly REPO_ROOT="$PWD"

# shellcheck source=pin.env
source ./pin.env

WORK_DIR="${WORK_DIR:-$REPO_ROOT/work}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/output}"
LOG_DIR="${LOG_DIR:-$REPO_ROOT/logs}"
KEEP_WORK="${KEEP_WORK:-0}"

# Persistent pacman package cache.
#
# This is a cache, not build state: every file in it is content-addressed and
# signature-verified by pacman before use, and a build with an empty cache
# produces the same ISO — it just re-downloads ~2GB. Deleting it is always safe.
# It exists because the Arch Linux Archive is a single slow host and a rebuild
# loop that re-fetches the whole package set each time makes the already long
# feedback cycle unusable (and hammers a volunteer-run service).
PKG_CACHE="${PKG_CACHE:-$REPO_ROOT/.cache/pacman-pkg}"

log() { printf '\033[1;36m[build]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m[build] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# --- container engine -------------------------------------------------------
# podman is preferred when present: it does not need the caller in a
# docker-equivalent group. Either works.
ENGINE="${CONTAINER_ENGINE:-}"
if [[ -z $ENGINE ]]; then
    if command -v podman >/dev/null 2>&1; then
        ENGINE=podman
    elif command -v docker >/dev/null 2>&1; then
        ENGINE=docker
    else
        die "need podman or docker on PATH (neither found)"
    fi
fi
command -v "$ENGINE" >/dev/null 2>&1 || die "container engine '$ENGINE' not on PATH"
"$ENGINE" info >/dev/null 2>&1 || die "'$ENGINE' is installed but its daemon is not reachable"
log "container engine: $ENGINE"

# --- preflight --------------------------------------------------------------
[[ -f "$PROFILE/profiledef.sh" ]] || die "no $PROFILE/profiledef.sh — run this from the repo root"

# The airootfs contains files that must land as root-owned symlinks and as
# mode-0400 shadow files. A build from a checkout on a filesystem that cannot
# represent symlinks would silently produce a broken image.
[[ -L "$PROFILE/airootfs/etc/systemd/system/multi-user.target.wants/NetworkManager.service" ]] \
    || die "airootfs symlinks did not survive checkout (NetworkManager.service is not a symlink)"

mkdir -p -- "$WORK_DIR" "$OUT_DIR" "$LOG_DIR" "$PKG_CACHE"

readonly BUILD_LOG="$LOG_DIR/build-$(date -u +%Y%m%dT%H%M%SZ).log"
log "log: $BUILD_LOG"
log "snapshot pin: $ARCH_SNAPSHOT (SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH)"

# work/ must be empty: mkarchiso refuses to reuse a dirty work dir, and a
# half-populated one from a failed run is the classic "it only builds on my
# machine" trap. Clearing it is what makes this a clean-state build.
if [[ -n $(ls -A -- "$WORK_DIR" 2>/dev/null) ]]; then
    log "clearing stale work dir $WORK_DIR"
    # Owned by root from the previous container run, so remove it in-container.
    "$ENGINE" run --rm -v "$WORK_DIR:/work" "$BUILDER_IMAGE" \
        find /work -mindepth 1 -delete
fi

# --- build ------------------------------------------------------------------
# --privileged: pacstrap mounts /proc, /sys and a devtmpfs inside the chroot.
# SOURCE_DATE_EPOCH is exported into the container so archiso derives a stable
# iso_version, iso_label and file mtimes from the pin rather than from "now".
log "starting mkarchiso (this takes roughly 20-40 min on a cold package cache)"

set +e
"$ENGINE" run --rm --privileged \
    -e "ARCH_SNAPSHOT=$ARCH_SNAPSHOT" \
    -e "SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH" \
    -e "BUILDER_PACKAGES=$BUILDER_PACKAGES" \
    -e "PROFILE=$PROFILE" \
    -v "$REPO_ROOT:/luminos" \
    -v "$WORK_DIR:/build/work" \
    -v "$OUT_DIR:/build/out" \
    -v "$PKG_CACHE:/var/cache/pacman/pkg" \
    -w /luminos \
    "$BUILDER_IMAGE" \
    bash -euo pipefail -c '
        printf "\n>>> pinning builder to Arch snapshot %s\n" "$ARCH_SNAPSHOT"
        # Point the builder at the frozen snapshot. Comment out any Include of
        # the live mirrorlist so nothing can reach a mirror-of-the-day.
        printf "Server = https://archive.archlinux.org/repos/%s/\$repo/os/\$arch\n" "$ARCH_SNAPSHOT" \
            > /etc/pacman.d/mirrorlist
        # The archive is a single host; parallel downloads against it are rude
        # and flaky. Serialise them.
        sed -i "s/^ParallelDownloads.*/ParallelDownloads = 1/" /etc/pacman.conf

        printf "\n>>> upgrading builder down to the snapshot\n"
        # -uu allows the downgrades needed to land exactly on the snapshot, so
        # the toolchain is part of the pin and not whatever the base image had.
        pacman -Syuu --noconfirm --needed

        printf "\n>>> installing builder toolchain\n"
        # shellcheck disable=SC2086
        pacman -S --noconfirm --needed $BUILDER_PACKAGES

        printf "\n>>> builder toolchain versions (these are part of the artifact provenance)\n"
        # shellcheck disable=SC2086
        pacman -Q archiso grub dosfstools mtools libisoburn squashfs-tools

        printf "\n>>> mkarchiso\n"
        exec mkarchiso -v -w /build/work -o /build/out "/luminos/$PROFILE"
    ' 2>&1 | tee -- "$BUILD_LOG"
rc=${PIPESTATUS[0]}
set -e

if (( rc != 0 )); then
    die "mkarchiso failed (exit $rc). Full log: $BUILD_LOG"
fi

# --- results ----------------------------------------------------------------
shopt -s nullglob
isos=("$OUT_DIR"/*.iso)
shopt -u nullglob
(( ${#isos[@]} )) || die "mkarchiso reported success but produced no ISO in $OUT_DIR"

iso="${isos[-1]}"
log "ISO: $iso"
log "size: $(du -h -- "$iso" | cut -f1)"

# Checksums live next to the ISO so the artifact is verifiable by whoever
# receives it, not just by whoever built it.
( cd -- "$OUT_DIR" && sha256sum -- "$(basename -- "$iso")" > "$(basename -- "$iso").sha256" )
log "sha256: $(cut -d' ' -f1 < "$iso.sha256")"

if [[ $KEEP_WORK != 1 ]]; then
    log "removing work dir (KEEP_WORK=1 to keep it)"
    "$ENGINE" run --rm -v "$WORK_DIR:/work" "$BUILDER_IMAGE" find /work -mindepth 1 -delete
fi

cat >&2 <<EOF

$(printf '\033[1;32m[build] SUCCESS\033[0m')
  ISO      : $iso
  sha256   : $iso.sha256
  log      : $BUILD_LOG
  snapshot : $ARCH_SNAPSHOT

Next: boot it. ./scripts/test-boot.sh uefi   |   ./scripts/test-boot.sh bios
EOF
