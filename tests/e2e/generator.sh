#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Generators run early; systemd-import-creds reads the QEMU SMBIOS value.
set -euo pipefail
[[ -d /run/archiso ]] || exit 0
# /run/archiso is created by the initramfs on the live ISO, never on the target.
out="${1:?systemd generator output directory}"
mkdir -p "$out/multi-user.target.wants"
cat > "$out/luminos-e2e.service" <<'UNIT'
[Unit]
Description=M6 headless installation on disposable VM disk
After=NetworkManager.service
Wants=NetworkManager.service
ConditionCredential=dawn.scenario
ConditionKernelCommandLine=archisobasedir
ConditionPathExists=/run/archiso
ConditionPathExists=/dev/disk/by-id/virtio-dawn-target
[Service]
Type=oneshot
ImportCredential=dawn.scenario
ExecStart=/usr/lib/luminos-e2e/install
TimeoutStartSec=40min
StandardOutput=journal+console
StandardError=journal+console
UNIT
ln -s ../luminos-e2e.service "$out/multi-user.target.wants/"
