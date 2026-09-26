#!/usr/bin/env bash
#
# Resolve every entry in releng/packages.x86_64 and bootstrap_packages.x86_64
# against the pinned snapshot, and report anything that no longer exists.
#
#   ./scripts/verify-packages.sh
#
# Run this before any build. It takes about 40 seconds, versus discovering the
# same thing 25 minutes into a mkarchiso run. It is also the check that catches
# bit-rot: a package silently leaving the Arch repos is the single most common
# reason an archiso profile stops building.
#
# Exits non-zero if anything is unresolvable, so it is usable as a gate.

set -euo pipefail

cd -- "$(dirname -- "$(readlink -f -- "$0")")/.."
# shellcheck source=../pin.env
source ./pin.env

ENGINE="${CONTAINER_ENGINE:-}"
if [[ -z $ENGINE ]]; then
    if command -v podman >/dev/null 2>&1; then ENGINE=podman
    elif command -v docker >/dev/null 2>&1; then ENGINE=docker
    else echo "need podman or docker" >&2; exit 1; fi
fi

echo "Verifying package set against Arch snapshot $ARCH_SNAPSHOT"

"$ENGINE" run --rm \
    -e "ARCH_SNAPSHOT=$ARCH_SNAPSHOT" \
    -v "$PWD/releng:/releng:ro" \
    "$BUILDER_IMAGE" \
    bash -euo pipefail -c '
        printf "Server = https://archive.archlinux.org/repos/%s/\$repo/os/\$arch\n" "$ARCH_SNAPSHOT" \
            > /etc/pacman.d/mirrorlist
        # multilib is in the profile pacman.conf, so check against it too.
        sed -i "s/^#\[multilib\]/[multilib]/; /^\[multilib\]/,+1 s/^#Include/Include/" /etc/pacman.conf
        sed -i "s/^ParallelDownloads.*/ParallelDownloads = 1/" /etc/pacman.conf
        pacman -Sy >/dev/null 2>&1

        rc=0
        # Parse exactly the way mkarchiso does, so this checks what will really
        # be handed to pacstrap -- including any accidental trailing whitespace.
        parse() { sed "/^[[:blank:]]*#.*/d;s/#.*//;/^[[:blank:]]*\$/d" "$1"; }

        for f in /releng/packages.x86_64 /releng/bootstrap_packages.x86_64; do
            printf "\n== %s ==\n" "$f"
            n=0; bad=0
            while IFS= read -r p; do
                n=$((n+1))
                if [[ "$p" != "${p// /}" ]]; then
                    printf "  WHITESPACE  %q\n" "$p"; bad=$((bad+1)); continue
                fi
                if ! pacman -Si -- "$p" >/dev/null 2>&1; then
                    if pacman -Sg -- "$p" >/dev/null 2>&1; then
                        printf "  GROUP       %s (a group, not a package -- pacstrap accepts it but it is unpinnable)\n" "$p"
                    else
                        printf "  MISSING     %s\n" "$p"; bad=$((bad+1))
                    fi
                fi
            done < <(parse "$f")
            printf "  %d entries, %d unresolvable\n" "$n" "$bad"
            (( bad == 0 )) || rc=1
        done
        exit $rc
    '

echo
echo "OK: every package resolves against snapshot $ARCH_SNAPSHOT"
