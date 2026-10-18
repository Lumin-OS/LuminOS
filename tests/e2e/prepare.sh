#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Disposable CI container only: freeze the packages once, then build the real
# profile against that snapshot. Guests never use a public mirror.
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work="${LUMINOS_E2E_WORK:-/tmp/luminos-e2e}"
mirror="$work/mirror"
profile="$work/profile"
published="${1:?usage: prepare.sh published-repository-dir public-key-file}"
key="${2:?usage: prepare.sh published-repository-dir public-key-file}"
[[ ! -e $work ]] || { echo "Use a fresh work directory: $work" >&2; exit 1; }
mkdir -p "$mirror" "$work/db" "$work/live" "$work/gnupg"
chmod 700 "$work/gnupg"
# The committed public key is independent of the published DB. Pin both source
# checkouts in the workflow; fail before downloading/installing on a bad signature.
gpg --homedir "$work/gnupg" --batch --import "$key"
gpg --homedir "$work/gnupg" --batch --verify \
    "$published/x86_64/luminos-repository.db.sig" "$published/x86_64/luminos-repository.db"
# Pacman must also know the replacement public key when it encounters
# the signed upstream DB/packages during snapshot population (CI only).
pacman-key --init
pacman-key --add "$key"
pacman-key --lsign-key 547F4761802A0904A0B10E5FAE527343BC3E39B3
# Authenticate the published binaries using the hashes in the signed database.
# Older uploads lack detached package signatures; do not invent signatures or
# change production pacman's policy to compensate.
python3 "$root/tests/e2e/verify-published.py" "$published/x86_64"

# Build the actual live-only package from this checkout, unprivileged.
chown -R builder:builder "$work/live" "$root/luminos-live"
runuser -u builder -- env PKGDEST="$work/live" BUILDDIR="$work/live/build" \
    makepkg --dir "$root/luminos-live" --nodeps --nosign --clean
repo-add "$work/live/luminos-iso.db.tar.gz" "$work/live"/*.pkg.tar.zst
cat > "$work/download.conf" <<CONF
[options]
Architecture = auto
SigLevel = Required DatabaseOptional
[core]
Include = /etc/pacman.d/mirrorlist
[extra]
Include = /etc/pacman.d/mirrorlist
[multilib]
Include = /etc/pacman.d/mirrorlist
[luminos-repository]
SigLevel = Optional TrustAll DatabaseOptional
Server = file://$published/x86_64
[luminos-iso]
SigLevel = Optional TrustAll
Server = file://$work/live
CONF
mapfile -t packages < <(sed 's/#.*//; /^[[:space:]]*$/d' "$root/releng/packages.x86_64")
# jq is a test helper; all production packages still come from the real recipes.
packages+=(jq)
# An empty DB resolves the full dependency closure, independent of host packages.
pacman --config "$work/download.conf" --dbpath "$work/db" --cachedir "$mirror" \
    -Syw --noconfirm "${packages[@]}"
repo-add "$mirror/dawnlocal.db.tar.gz" "$mirror"/*.pkg.tar.zst
(cd "$mirror" && sha256sum -- *.pkg.tar.zst dawnlocal.db.tar.gz > SHA256SUMS)
cat > "$work/build.conf" <<CONF
[options]
Architecture = auto
SigLevel = Optional TrustAll
[dawnlocal]
Server = file://$mirror
CONF
cp -a "$root/releng" "$profile"
cp "$work/build.conf" "$profile/airootfs/etc/pacman.conf"
sed -i "s|file://$mirror|http://10.0.2.2:8080|" "$profile/airootfs/etc/pacman.conf"
echo jq >> "$profile/packages.x86_64"
# Install the CI service under /run at boot, not into the image: an offline
# copy must never retain a service that wipes its new disk on the next boot.
install -Dm755 "$root/tests/e2e/install.sh" "$profile/airootfs/usr/lib/luminos-e2e/install"
# Run once from a generator, enabled only by a VM-specific SMBIOS credential.
install -Dm755 "$root/tests/e2e/generator.sh" \
    "$profile/airootfs/usr/lib/systemd/system-generators/luminos-e2e"
{
    echo 'airootfs_image_tool_options=("-comp" "zstd" "-Xcompression-level" "1" "-b" "1M")'
    echo 'file_permissions["/usr/lib/luminos-e2e/install"]="0:0:755"'
    echo 'file_permissions["/usr/lib/systemd/system-generators/luminos-e2e"]="0:0:755"'
} >> "$profile/profiledef.sh"
sed -i '/^[[:space:]]*linux /s/$/ console=tty0 console=ttyS0,115200n8/' "$profile/grub/grub.cfg"
chown -R builder:builder "$work" "$root"
runuser -u builder -- env LUMINOS_PROFILE_DIR="$profile" \
    LUMINOS_PACMAN_CONF="$work/build.conf" bash "$root/build.sh"
# Free the uncompressed live tree before the three target disks are created.
rm -rf -- "$root/work"
