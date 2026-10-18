#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Only runs in the disposable guest; the actual published backend retains all
# its disk safety checks. Test password is never echoed or sent as a CLI arg.
set -euo pipefail
scenario=$(cat "$CREDENTIALS_DIRECTORY/dawn.scenario")
case "$scenario" in online|offline|secure-boot) ;; *) exit 2 ;; esac
[[ -d /run/archiso && -e /dev/disk/by-id/virtio-dawn-target ]]
plan=/run/luminos-e2e-plan.json
trap 'rm -f "$plan"' EXIT
source=pacstrap
[[ $scenario != offline ]] || source=squashfs
secure=false
[[ $scenario != secure-boot ]] || secure=true
umask 077
jq -n --arg source "$source" --argjson secure "$secure" '{
  version: 1, locale: "en_US.UTF-8", keyboard: {layout: "us", variant: ""},
  timezone: "Europe/Berlin", hostname: "luminos-m6", source: $source,
  packages: ["luminos-base", "luminos-desktop"],
  disk: {mode: "erase", device: "/dev/disk/by-id/virtio-dawn-target", filesystem: "btrfs"},
  secure_boot: {enroll: $secure, microsoft_keys: true},
  user: {full_name: "Ada Lovelace", username: "ada",
    password: "correct-horse-battery-staple", autologin: false}
}' > "$plan"
# Keep the plan private without changing permissions created by pacstrap.
umask 022
if [[ $scenario == offline ]]; then
    # QEMU attaches no NIC; assert that isolation rather than trusting a label.
    [[ $(find /sys/class/net -mindepth 1 -maxdepth 1 | wc -l) == 1 ]]
else
    nm-online --quiet --timeout=60
    # A headless plan can start before the live keyring's initial import
    # finishes. Wait for the real ISO service; do not bypass signature checks.
    timeout 180 systemctl start pacman-init.service
    curl --fail --retry 15 --retry-connrefused --retry-delay 2 http://10.0.2.2:8080/dawnlocal.db -o /dev/null
fi
/usr/bin/dawn-backend --target /dev/disk/by-id/virtio-dawn-target "$plan"
# Remove CI-only fixture files copied from the live image. The service itself
# is generated under /run, so it cannot survive squashfs installation.
mapfile -t roots < <(lsblk -rno PATH,FSTYPE /dev/disk/by-id/virtio-dawn-target | awk '$2 == "btrfs" {print $1}')
[[ ${#roots[@]} == 1 ]]
cleanup_root=$(mktemp -d /run/luminos-e2e-root-XXXXXX)
mount -o subvol=@ "${roots[0]}" "$cleanup_root"
rm -f "$cleanup_root/usr/lib/luminos-e2e/install" \
    "$cleanup_root/usr/lib/systemd/system-generators/luminos-e2e"
umount "$cleanup_root"
rmdir "$cleanup_root"
sync
echo DAWN-E2E-INSTALL-OK
