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
repo-add "$repo/luminos-iso.db.tar.gz" "$repo"/luminos-live-*.pkg.tar.*

# Only the build sees this repository. The live system's own pacman.conf
# (releng/airootfs/etc/pacman.conf) doesn't list it, so nothing installed
# from the ISO can get luminos-live again.
cat "$root/releng/pacman.conf" - > "$work/pacman.conf" <<EOF

[luminos-iso]
SigLevel = Optional TrustAll
Server = file://$repo
EOF

sudo mkarchiso -v -C "$work/pacman.conf" -w "$work" -o "$root/output" "$root/releng"
