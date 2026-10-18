# LuminOS

LuminOS is yet another Archiso, with Hyprland and its own installer, Dawn.
Serves as a bachelor's thesis project.

This repository builds the ISO:

- `releng/`: the archiso profile, based on Arch's releng. The live user
  `luminos` is logged in on tty1 and gets Hyprland, which opens Dawn. Its
  Hyprland config (`airootfs/home/luminos/.config/hypr/hyprland.lua`)
  loads luminos-desktop's defaults and adds Dawn's window rule, autostart
  and launcher bind (Super+I). Idle locking is disabled for the live user.
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

## M5 integration check

`.github/workflows/m5-iso.yml` builds the real packages and this profile in
an isolated CI container, then boots it with QEMU/OVMF. A service added only
to the copied test profile waits until Hyprland reports a mapped
`luminos-dawn` window. The production profile contains no observer service.
The boot log is uploaded as `m5-real-iso-boot`.

For an integration build before publication, set `LUMINOS_PACKAGE_DIR` to
a directory containing locally built `.pkg.tar.zst` packages. `build.sh`
adds them to its temporary repository ahead of the published repository.
`LUMINOS_PROFILE_DIR` can select a copied profile. Neither setting changes
the pacman configuration inside the resulting image; online installs still
require the packages to be published. Sign and publish all four packages
before distributing a release ISO.

The matching implementation is reviewed in [Dawn #11](https://github.com/Lumin-OS/dawn/pull/11),
[packaging #3](https://github.com/Lumin-OS/luminos-packages/pull/3), and
[dotfiles #2](https://github.com/Lumin-OS/dotfiles/pull/2). Merge those
providers before this ISO change.

## M6 nightly installation checks

The [real-ISO end-to-end workflow](.github/workflows/m6-e2e.yml) builds the
production profile against one frozen package snapshot, then installs online,
offline without a NIC, and with Secure Boot in disposable QEMU guests. Every
installed disk must boot without its ISO or mirror and accept the new user's
login; Secure Boot must enforce in its scenario. Logs, source revisions and
package hashes are uploaded for failures as well as successful runs.

See [the test instructions](tests/e2e/README.md) for the CI environment,
snapshot trust model and fixture isolation. `LUMINOS_PACMAN_CONF` lets CI
select a local snapshot for the build; the default build configuration stays
`releng/pacman.conf`. Guests use a snapshot-only pacman config added to a
copied test profile. Merge the [Dawn helpers](https://github.com/Lumin-OS/dawn/pull/12)
and [keyring rotation](https://github.com/Lumin-OS/luminos-packages/pull/4)
before the consuming ISO change.
