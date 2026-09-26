#!/usr/bin/env bash
#
# Boot a LuminOS ISO in QEMU and prove it reaches the session.
#
#   ./scripts/test-boot.sh uefi            # OVMF firmware
#   ./scripts/test-boot.sh bios            # SeaBIOS / legacy
#   ./scripts/test-boot.sh uefi --graphical  # interactive window, no timeout
#
# An ISO that builds but does not boot is a failed build, so this is not
# optional tooling. Default mode is headless: it captures the serial console to
# a log, waits for evidence that the graphical session came up, screenshots the
# VM display, then shuts down. That gives an artifact you can attach to a ticket
# rather than "it worked on my screen".
#
# It never touches a host disk. The only block device handed to the VM is the
# ISO, read-only, plus an optional scratch qcow2 under logs/.

set -euo pipefail

cd -- "$(dirname -- "$(readlink -f -- "$0")")/.."

MODE="${1:-uefi}"
shift || true
GRAPHICAL=0
TIMEOUT="${TIMEOUT:-420}"
for a in "$@"; do
    case "$a" in
        --graphical) GRAPHICAL=1 ;;
        *) echo "unknown option: $a" >&2; exit 2 ;;
    esac
done
case "$MODE" in uefi|bios) ;; *) echo "usage: $0 {uefi|bios} [--graphical]" >&2; exit 2 ;; esac

command -v qemu-system-x86_64 >/dev/null || { echo "ERROR: qemu-system-x86_64 not found" >&2; exit 1; }

# --- locate the ISO ---------------------------------------------------------
ISO="${ISO:-}"
if [[ -z $ISO ]]; then
    shopt -s nullglob
    cands=(output/*.iso)
    shopt -u nullglob
    (( ${#cands[@]} )) || { echo "ERROR: no ISO in output/. Run ./build.sh first." >&2; exit 1; }
    ISO="${cands[-1]}"
fi
[[ -f $ISO ]] || { echo "ERROR: $ISO not found" >&2; exit 1; }

stamp=$(date -u +%Y%m%dT%H%M%SZ)
outdir="logs/boot-$MODE-$stamp"
mkdir -p -- "$outdir"
serial="$outdir/serial.log"
shot="$outdir/screen.ppm"
shotpng="$outdir/screen.png"

echo "ISO      : $ISO"
echo "mode     : $MODE"
echo "evidence : $outdir/"

# --- firmware ---------------------------------------------------------------
fw=()
if [[ $MODE == uefi ]]; then
    ovmf=""
    for c in /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/edk2/x64/OVMF_CODE.fd \
             /usr/share/edk2-ovmf/x64/OVMF_CODE.fd /usr/share/OVMF/OVMF_CODE.fd \
             /usr/share/qemu/edk2-x86_64-code.fd; do
        [[ -f $c ]] && { ovmf="$c"; break; }
    done
    [[ -n $ovmf ]] || {
        echo "ERROR: no OVMF firmware found. Install 'edk2-ovmf' to test UEFI." >&2
        exit 1
    }
    vars=""
    for c in /usr/share/edk2/x64/OVMF_VARS.4m.fd /usr/share/edk2/x64/OVMF_VARS.fd \
             /usr/share/edk2-ovmf/x64/OVMF_VARS.fd /usr/share/OVMF/OVMF_VARS.fd; do
        [[ -f $c ]] && { vars="$c"; break; }
    done
    echo "firmware : $ovmf"
    # Copy the vars store: the VM writes its EFI variables there and the
    # system-wide template must stay pristine.
    if [[ -n $vars ]]; then
        cp -- "$vars" "$outdir/OVMF_VARS.fd"
        fw=(-drive "if=pflash,format=raw,readonly=on,file=$ovmf"
            -drive "if=pflash,format=raw,file=$outdir/OVMF_VARS.fd")
    else
        fw=(-bios "$ovmf")
    fi
else
    echo "firmware : SeaBIOS (qemu default)"
fi

# --- accel ------------------------------------------------------------------
accel=(-machine "type=q35,accel=tcg")
if [[ -w /dev/kvm ]]; then
    accel=(-machine "type=q35,accel=kvm" -cpu host)
    echo "accel    : kvm"
else
    echo "accel    : tcg (no /dev/kvm; this will be slow)"
fi

qemu=(
    qemu-system-x86_64
    "${accel[@]}" "${fw[@]}"
    -m 4096
    -smp 2
    # cdrom, read-only, and no other block device. Nothing here can reach a
    # host disk.
    -drive "file=$ISO,media=cdrom,readonly=on,if=none,id=iso"
    -device ide-cd,drive=iso,bootindex=1
    # virtio-vga gives a DRM device Hyprland can use, rendered by mesa's
    # software path inside the guest. virtio-gpu-gl would need host GL.
    -device virtio-vga
    -device virtio-net-pci,netdev=n0
    # user-mode networking: the guest gets DHCP + DNS + outbound NAT with no
    # host bridge and no privileges. Enough to prove NetworkManager works.
    -netdev user,id=n0
    -device qemu-xhci
    -device usb-tablet
    -rtc base=utc
)

if (( GRAPHICAL )); then
    echo
    echo "Launching interactive window. Close it or press Ctrl+C when done."
    exec "${qemu[@]}" -serial "file:$serial" -display gtk
fi

# Headless: serial to file, QMP on a socket so we can screenshot and power off.
qmp="$outdir/qmp.sock"
"${qemu[@]}" \
    -display none \
    -serial "file:$serial" \
    -qmp "unix:$qmp,server=on,wait=off" \
    & qpid=$!

cleanup() {
    if kill -0 "$qpid" 2>/dev/null; then
        kill "$qpid" 2>/dev/null || true
        wait "$qpid" 2>/dev/null || true
    fi
}
trap cleanup EXIT

qmp_cmd() {
    # One-shot QMP exchange: negotiate capabilities, then send the command.
    printf '{"execute":"qmp_capabilities"}\n%s\n' "$1" \
        | timeout 20 socat - "UNIX-CONNECT:$qmp" 2>/dev/null || true
}

# --- wait for the session ---------------------------------------------------
# Reaching the compositor is the acceptance criterion. The serial log proves the
# system reached multi-user; the screenshot proves the session actually came up,
# because the compositor renders to the VM display and never to serial.
echo
echo "waiting up to ${TIMEOUT}s for the session (polling $serial)"
deadline=$(( SECONDS + TIMEOUT ))
reached=""
last=""
while (( SECONDS < deadline )); do
    if ! kill -0 "$qpid" 2>/dev/null; then
        echo "!! QEMU exited early"; break
    fi
    if [[ -f $serial ]]; then
        # Progress markers, so a failure reports WHERE in the boot chain it
        # stopped rather than just "timed out". These are the things that do
        # reach serial: firmware -> bootloader -> kernel -> userspace.
        for marker in 'BdsDxe: starting|Booting from' 'GNU GRUB' 'Linux version|\[    0\.0' 'systemd'; do
            if grep -qE "$marker" "$serial" 2>/dev/null && [[ $last != "$marker" ]]; then
                echo "  .. saw: $marker"; last="$marker"
            fi
        done
        # What is actually visible on serial.
        #
        # The kernel cmdline is `console=ttyS0,115200 console=tty0`, and the
        # LAST console= wins for /dev/console -- deliberately tty0, so that a
        # user staring at a screen sees boot messages and any emergency prompt.
        # The consequence is that systemd's own log goes to tty0, NOT here, so
        # waiting for "Startup finished" on serial waits forever even on a
        # perfectly good boot. (It did, on the first candidate.)
        #
        # What DOES reach serial is serial-getty@ttyS0, which systemd only
        # starts once multi-user.target is up. So its login prompt is sound
        # evidence that the system reached multi-user.
        if grep -qE 'LuminOS login:|[a-z]+ login:' "$serial" 2>/dev/null; then
            reached=1
            break
        fi
    fi
    sleep 5
done

# Give the compositor a moment past systemd's "startup finished" before we
# photograph the screen, otherwise we capture the tty mid-handoff.
if [[ -n $reached ]]; then
    echo "  .. reached multi-user (serial getty is up); allowing 45s for Hyprland"
    sleep 45
fi

# --- capture evidence -------------------------------------------------------
if command -v socat >/dev/null; then
    qmp_cmd "{\"execute\":\"screendump\",\"arguments\":{\"filename\":\"$PWD/$shot\"}}" >/dev/null
    sleep 3
    if [[ -f $shot ]]; then
        echo "screenshot: $shot"
        if command -v magick >/dev/null; then magick "$shot" "$shotpng" && echo "screenshot: $shotpng"
        elif command -v convert >/dev/null; then convert "$shot" "$shotpng" && echo "screenshot: $shotpng"
        elif command -v ffmpeg >/dev/null; then ffmpeg -loglevel error -y -i "$shot" "$shotpng" && echo "screenshot: $shotpng"
        fi
    fi
else
    echo "NOTE: socat not installed, cannot screenshot via QMP" >&2
fi

echo
if [[ -n $reached ]]; then
    echo "RESULT: booted to a running system under $MODE"
else
    echo "RESULT: FAILED to confirm boot under $MODE within ${TIMEOUT}s"
fi
echo "serial log tail:"
tail -25 -- "$serial" 2>/dev/null | sed 's/^/  /' || echo "  (no serial output at all — failed before the kernel took the console)"

cleanup
trap - EXIT
[[ -n $reached ]]
