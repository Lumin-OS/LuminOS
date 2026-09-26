# Building LuminOS

## The command

```bash
./build.sh
```

That is all of it, from a clean checkout. No `archiso` on the host, no root, no
prior state. The ISO lands in `output/` with a `.sha256` next to it.

Then verify it boots — an ISO that builds but does not boot is a failed build,
not a partial success:

```bash
./scripts/test-boot.sh uefi
./scripts/test-boot.sh bios
```

## Requirements

| Need | Why |
|---|---|
| `podman` or `docker` | The build runs in a container. `build.sh` prefers podman. |
| ~25 GB free disk | `work/` peaks around 12–15 GB; the ISO is ~2.5 GB. |
| Network | Fetches the pinned package snapshot. Cached after the first run. |
| `qemu-system-x86_64`, `edk2-ovmf`, `socat` | Boot verification only, not the build. |

You do **not** need to be on Arch. That is the point of the container.

## Why the build runs in a container

Two reasons, and the second is the important one.

1. `mkarchiso` needs root and a real Arch `pacman` with an Arch keyring. The
   founder's build machine is CachyOS, whose `pacman.conf` carries the
   `cachyos*` and `*-znver4` repos. Building there would silently pull
   CachyOS-optimised packages into a distribution that claims to be Arch-based,
   and `archiso` is not installable on that host without an interactive sudo
   password anyway.

2. **Reproducibility.** The container is pinned by digest and then upgraded down
   to a frozen Arch Linux Archive snapshot, so the *build toolchain* is pinned to
   the same day as the *image contents*. A build on a developer's own Arch box
   uses whatever `archiso`, `grub` and `mksquashfs` that box happens to have.

## How pinning works

Everything version-bearing lives in **`pin.env`**. Nothing else in the repo
contains a version.

```
ARCH_SNAPSHOT="2026/09/25"     # frozen Arch Linux Archive snapshot
SOURCE_DATE_EPOCH="1790294400" # 00:00:00 UTC on that day
BUILDER_IMAGE="archlinux@sha256:..."
```

`archiso` has no per-package version syntax in `packages.x86_64`, so the only way
to pin a package set is to pin the *repository*. `releng/pacman.conf` therefore
points all three repos at one archive snapshot instead of `Include`-ing
`/etc/pacman.d/mirrorlist`.

This is the direct fix for how this profile rotted. Between February 2024 and
September 2026 six of its packages left the Arch repos, and because the profile
pinned nothing there was no record of a version set that had ever worked.

`SOURCE_DATE_EPOCH` is consumed by `archiso` for `iso_version`, `iso_label` and
file mtimes, so the artifact name and volume label are stable across rebuilds.

### Bumping to a newer Arch

1. Pick a date that exists under <https://archive.archlinux.org/repos/>.
2. Update `ARCH_SNAPSHOT` **and** `SOURCE_DATE_EPOCH` in `pin.env`.
3. Update the three `Server =` lines in `releng/pacman.conf` to match.
4. `./scripts/verify-packages.sh` — catches packages dropped upstream in ~40s.
5. `./build.sh`, then `./scripts/test-boot.sh uefi` and `bios`.

Do not bump one of those without the others.

## Check the package set before building

```bash
./scripts/verify-packages.sh
```

Resolves every entry in `packages.x86_64` and `bootstrap_packages.x86_64`
against the pinned snapshot and exits non-zero if anything is unresolvable. It
parses the files exactly the way `mkarchiso` does, so it also catches the
trailing-whitespace trap described below. Forty seconds here beats discovering a
missing package 25 minutes into a build.

### The trailing-comment trap

`mkarchiso` parses the package list with:

```
sed '/^[[:blank:]]*#.*/d;s/#.*//;/^[[:blank:]]*$/d'
```

That strips a trailing comment but **leaves the whitespace before it**, and the
padded string goes to `pacstrap` verbatim as a package name. So this breaks:

```
hyprland            # compositor
```

Put comments on their own line. `verify-packages.sh` flags any line that would
hit this.

## Boot modes

`archiso` 90 renamed every boot mode this profile used in 2024. The six old
entries collapse to two:

| Old (deprecated) | Current |
|---|---|
| `bios.syslinux.mbr`, `bios.syslinux.eltorito` | `bios.syslinux` |
| `uefi-{ia32,x64}.grub.{esp,eltorito}` | `uefi.grub` |

`uefi.grub` covers IA32 and x64 and emits both the ESP and the El Torito image,
so BIOS and UEFI are both still covered by two entries.

LuminOS uses **grub** for UEFI rather than systemd-boot (which is what upstream
`archiso` now defaults to) because the branded boot menu lives in
`releng/grub/grub.cfg`. `archiso` rejects combining `uefi.grub` with
`uefi.systemd-boot` — it is one or the other. The `releng/efiboot/loader/`
systemd-boot entries are retained but unused; they are there if LuminOS ever
switches.

The builder therefore needs `grub` installed, which is what the original as-is
failure was complaining about:

```
ERROR: Validating 'uefi-ia32.grub.esp': grub-install is not available on this host. Install 'grub'!
```

## Serial console

All boot entries carry `console=ttyS0,115200 console=tty0`. The last `console=`
wins for `/dev/console`, so the screen stays primary and serial gets a copy.

This exists so boot verification can be automated and so a failed boot is not a
black box — `scripts/test-boot.sh` watches the serial log to find out *where* in
the boot chain a failure happened rather than just reporting a timeout.

## Layout

```
build.sh                    the only command you need
pin.env                     every version in the project
dotfiles.pin                which dotfiles commit is vendored in
releng/                     the archiso profile
  profiledef.sh             boot modes, image options, file permissions
  packages.x86_64           the package set
  pacman.conf               BUILD-TIME pacman: pinned to the archive snapshot
  airootfs/                 files copied into the live image
    etc/pacman.conf         LIVE-SYSTEM pacman: normal mirrors, not pinned
scripts/
  verify-packages.sh        does the package set still resolve?
  test-boot.sh              boot it in QEMU and capture evidence
  sync-dotfiles.sh          vendor Lumin-OS/dotfiles into the profile
docs/
  BUILDING.md               this file
  REPOSITORY.md             the custom package repository, and why it is off
```

### Two pacman.confs, on purpose

- `releng/pacman.conf` — used by `mkarchiso` to **populate the image**. Pinned to
  the archive snapshot so the ISO is reproducible.
- `releng/airootfs/etc/pacman.conf` — what the **live system runs with**. Normal
  mirrors, because the installer running from this medium installs a system the
  user expects to be current, and because pacstrapping a real machine through the
  archive would be painfully slow.

Pinning is a property of how the ISO is built, not of what the user ends up
running.

## Outputs

| Path | Contents |
|---|---|
| `output/luminos-*.iso` | the image |
| `output/luminos-*.iso.sha256` | checksum, written by `build.sh` |
| `logs/build-*.log` | full `mkarchiso` output, including toolchain versions |
| `logs/boot-*/` | serial log + screenshot per boot test |
| `.cache/pacman-pkg/` | package cache; safe to delete at any time |

`work/` is cleared at the start of every build and removed at the end
(`KEEP_WORK=1` to keep it for inspection). A build must never depend on state
left behind by a previous one.

## Troubleshooting

**`grub-install is not available`** — the builder is missing `grub`. It is listed
in `BUILDER_PACKAGES` in `pin.env`; check it was not removed.

**`error: target not found: <name>`** — a package left the Arch repos. Run
`./scripts/verify-packages.sh` to get the full list at once instead of one per
build.

**`target not found: <name>` with trailing spaces in the name** — the
trailing-comment trap above.

**Build dies in `pacstrap` with mount errors** — the container is not privileged.
`pacstrap` mounts `/proc`, `/sys` and a devtmpfs inside the chroot.

**Black screen after the boot menu** — diagnose in boot-chain order: firmware →
bootloader → kernel → initramfs → root → session. Check the serial log in
`logs/boot-*/serial.log` first; if systemd reached multi-user then the failure is
in the session, and the compositor's own log is at
`/run/user/1000/hypr/*/hyprland.log` inside the VM.
