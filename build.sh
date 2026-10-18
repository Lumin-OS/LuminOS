#!/usr/bin/env bash
#
# Builds the LuminOS ISO into output/. First luminos-live (luminos-live/),
# into a pacman repository only this build uses, then the releng profile
# with mkarchiso, with that repository added to its pacman.conf.
#
# Run it as a normal user: makepkg refuses to run as root, and mkarchiso
# gets root through sudo. Needs archiso, base-devel, and grub, since
# mkarchiso makes the UEFI boot loader with this machine's
# grub-mkstandalone.

set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
work="$root/work"
repo="$work/luminos-iso-repo"

if (( EUID == 0 )); then
    echo "build.sh: run this as a normal user; makepkg refuses to run as root" >&2
    exit 1
fi

# mkarchiso skips every step it finds already done in its work directory.
sudo rm -rf -- "$work"
mkdir -p -- "$repo"

# --nodeps: the dependencies are the live system's, not this machine's.
BUILDDIR="$work/makepkg" PKGDEST="$repo" \
    makepkg --dir "$root/luminos-live" --nodeps --nosign --clean
# Optional local builds for integration testing before publication. They
# override the public repository only while mkarchiso builds the image.
if [[ -n ${LUMINOS_PACKAGE_DIR:-} ]]; then
    cp -- "$LUMINOS_PACKAGE_DIR"/*.pkg.tar.zst "$repo/"
fi
repo-add "$repo/luminos-iso.db.tar.gz" "$repo"/*.pkg.tar.zst

# Only the build sees this repository. The live system's own pacman.conf
# (releng/airootfs/etc/pacman.conf) doesn't list it, so nothing installed
# from the ISO can get luminos-live again.
awk -v repo="$repo" '
    /^\[luminos-repository\]/ {
        print "[luminos-iso]\nSigLevel = Optional TrustAll\nServer = file://" repo "\n"
    }
    { print }
' "${LUMINOS_PACMAN_CONF:-$root/releng/pacman.conf}" > "$work/pacman.conf"

# A disposable copied profile lets CI add a boot observer without
# putting test services on production media.
profile="${LUMINOS_PROFILE_DIR:-$root/releng}"
sudo mkarchiso -v -C "$work/pacman.conf" -w "$work" -o "$root/output" "$profile"
