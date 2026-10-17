#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Boot the actual ISO with the CI observer, without attaching a target disk.
set -euo pipefail
iso="$(realpath "${1:?usage: boot-dawn.sh image.iso}")"
log="${2:-$PWD/boot-dawn.log}"
[[ -e /dev/kvm ]] || { echo "KVM is required" >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
cp /usr/share/edk2-ovmf/x64/OVMF_VARS.4m.fd "$work/vars.fd"
# Status 124 is reported below together with the serial log.
status=0
: > "$log"
timeout 300 qemu-system-x86_64 -enable-kvm -machine q35 -cpu host -smp 2 -m 4096 \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2-ovmf/x64/OVMF_CODE.4m.fd \
    -drive if=pflash,format=raw,file="$work/vars.fd" \
    -cdrom "$iso" -boot d -vga virtio -display none -serial "file:$log" -no-reboot \
    || status=$?
cat "$log"
(( status == 0 )) && grep -q 'LUMINOS-M5: Dawn window is mapped in Hyprland' "$log"
