# LuminOS

LuminOS is yet another Archiso, with Hyprland and its own installer, Dawn.
Serves as a bachelor's thesis project.

This repository builds the ISO:

- `releng/`: the archiso profile, based on Arch's releng. The live user
  `luminos` is logged in on tty1 and gets Hyprland, which opens Dawn. Its
  Hyprland config (`airootfs/home/luminos/.config/hypr/hyprland.lua`)
  holds Dawn's window rule, autostart and launcher bind (Super+I).
- `luminos-live/`: a package with the live system's own parts (keyring
  reset, autologin, live-only services and tools). An offline install
  removes it, so none of that reaches the installed system.

## Building

```sh
./build.sh
```

Run it as a normal user; it asks for sudo for mkarchiso. It needs
`archiso`, `grub` and `base-devel`, and puts the ISO in `output/`.

The ISO installs `luminos-base`, `luminos-desktop`, `luminos-keyring` and
`luminos-dawn` from [luminos-repository](https://github.com/Lumin-OS/luminos-repository).
Once that repository is signed, the build machine's pacman keyring needs
its key as well.
