# The live desktop: Hyprland on tty1, where the live user is logged in
# automatically (luminos-live's autologin). The speech boot entry
# (accessibility=on) stays on the console, where the speakup screen
# reader works.
if [[ -z $WAYLAND_DISPLAY && $XDG_VTNR == 1 ]] \
    && ! grep -Fqa 'accessibility=' /proc/cmdline; then
    # The live account is baked into passwd rather than created by
    # useradd, so copy the package's defaults on first login. Keep the
    # profile's live-only Hyprland overlay already present in this home.
    cp -r --update=none -- /etc/skel/.config/. "$HOME/.config/"
    export LUMINOS_LIVE=1
    exec start-hyprland
fi
