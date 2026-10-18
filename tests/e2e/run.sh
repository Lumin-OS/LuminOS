#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Reuse Dawn's serial login / Secure Boot verification with the real ISO.
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work="${LUMINOS_E2E_WORK:-/tmp/luminos-e2e}"
dawn="${DAWN_SOURCE_DIR:?set DAWN_SOURCE_DIR to the pinned Dawn checkout}"
scenario="${1:?usage: run.sh online|offline|secure-boot}"
case "$scenario" in online|offline|secure-boot) ;; *) exit 2 ;; esac
export DAWN_E2E_REAL_ISO=1 DAWN_E2E_MEMORY=6144
mapfile -t images < <(find "$root/output" -maxdepth 1 -name '*.iso')
[[ ${#images[@]} == 1 ]] || { echo 'Expected exactly one ISO' >&2; exit 1; }
(cd "$work/mirror" && sha256sum -c SHA256SUMS > /dev/null)
pid=""
cleanup() {
    [[ -z $pid ]] || kill "$pid" 2>/dev/null || true
    rm -f -- "$work/target-$scenario.qcow2" "$work/vars-$scenario.fd"
}
trap cleanup EXIT
if [[ $scenario != offline ]]; then
    "$dawn/tests/e2e/serve-mirror.sh" "$work/mirror" "$work/http-server.pid"
    pid=$(cat "$work/http-server.pid")
fi
qemu-img create -f qcow2 "$work/target-$scenario.qcow2" 48G
"$dawn/tests/e2e/qemu-run.sh" install "${images[0]}" "$work/target-$scenario.qcow2" \
    "$work/vars-$scenario.fd" "$scenario" "$work/install-$scenario.log" 2400
if grep -q 'correct-horse-battery-staple' "$work/install-$scenario.log"; then
    echo 'Test password leaked to install log' >&2
    exit 1
fi
# The snapshot is no longer served while booting the installed disk.
if [[ -n $pid ]]; then kill "$pid"; pid=""; fi
report=$("$dawn/tests/e2e/qemu-run.sh" verify-login "$work/target-$scenario.qcow2" \
    "$work/vars-$scenario.fd" "$scenario" "$work/login-$scenario.log" \
    ada correct-horse-battery-staple 360)
expected=0
[[ $scenario != secure-boot ]] || expected=1
[[ $report == "DAWN-E2E-LOGGED-IN secure_boot=$expected" ]]
echo "$scenario: $report"
