# The live desktop: Hyprland on tty1, where the live user is logged in
# automatically (luminos-live's autologin). The speech boot entry
# (accessibility=on) stays on the console, where the speakup screen
# reader works.
if [[ -z $WAYLAND_DISPLAY && $XDG_VTNR == 1 ]] \
    && ! grep -Fqa 'accessibility=' /proc/cmdline; then
    exec start-hyprland
fi
