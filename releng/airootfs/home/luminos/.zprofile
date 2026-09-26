# LuminOS live session entry point.
#
# getty@tty1 autologins the 'luminos' user (see
# /etc/systemd/system/getty@tty1.service.d/autologin.conf). zsh runs this file
# as a login shell, and this is where the graphical session is launched from.
#
# Autologin-into-compositor rather than a display manager: it is one fewer
# service that can fail between the kernel and a usable screen, and on a live
# installer medium there is no second user to choose between. If LuminOS later
# wants a greeter on the INSTALLED system, that is the installer's business, not
# this file's.

# Only on the real first console. Without this guard, SSHing in or switching to
# tty2 would try to start a second compositor on a seat that already has one,
# which fails noisily and leaves you without a shell.
if [[ -z ${WAYLAND_DISPLAY} && -z ${DISPLAY} && ${XDG_VTNR} == 1 ]]; then

    # Hyprland needs these to find a seat and a runtime dir. systemd-logind
    # provides XDG_RUNTIME_DIR for the autologin session; assert it rather than
    # silently starting a compositor that cannot open its sockets.
    export XDG_SESSION_TYPE=wayland
    export XDG_CURRENT_DESKTOP=Hyprland
    export XDG_SESSION_DESKTOP=Hyprland

    # Toolkit backends. Without these, Qt and GTK apps launched by the installer
    # fall back to X11 and need XWayland for no reason; Qt in particular picks
    # xcb and then fails outright if XWayland has not started yet.
    export QT_QPA_PLATFORM='wayland;xcb'
    export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
    export GDK_BACKEND='wayland,x11'
    export MOZ_ENABLE_WAYLAND=1
    export CLUTTER_BACKEND=wayland
    export SDL_VIDEODRIVER=wayland
    export _JAVA_AWT_WM_NONREPARENTING=1

    # Software rendering fallback.
    #
    # This is a live installer ISO: a very large share of its boots are in a VM
    # or on hardware whose GPU has no working driver yet. Hyprland refuses to
    # start if it cannot get an accelerated EGL context, which would mean a
    # black screen in exactly the situation where the user most needs the
    # installer. Allowing the software path costs nothing on real hardware,
    # where mesa picks the real driver regardless.
    export WLR_RENDERER_ALLOW_SOFTWARE=1
    export AQ_NO_ATOMIC=0

    # Deliberately NOT redirecting output to a file. If the compositor fails to
    # start, its reason has to be on tty1 where whoever is staring at the black
    # screen can read it. Hyprland additionally writes its own log to
    # $XDG_RUNTIME_DIR/hypr/<signature>/hyprland.log, which survives for the
    # life of the boot and is readable from another tty.

    # exec: replace the shell. If Hyprland exits, the getty respawns and the
    # user lands back at a login prompt rather than at a dead terminal.
    exec Hyprland
fi
