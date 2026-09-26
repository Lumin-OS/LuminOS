# The LuminOS custom package repository

Status: **not wired into the image, deliberately.** This document is the record of
why, and exactly what has to happen to turn it on.

Repo: [`Lumin-OS/luminos-repository`](https://github.com/Lumin-OS/luminos-repository)
(last push April 2024).

## What is actually in it

| Package | Version | Note |
|---|---|---|
| `calamares` | 3.3.1-1 | superseded — the installer is now `Felix-1871/dawn` |
| `calamares-git` | 3.3.5.r28 | ditto |
| `calamares-settings` | 1.r.992235a | ditto, 18 MB of it |
| `ckbcomp` | 1.221-1 | console keymap → X keymap; a Calamares dependency |
| `contour` | 0.4.3.6442 | terminal emulator |
| `eww` | 0.5.0-2 | widget system |
| `yay` | 12.3.1-2 | AUR helper |
| `mkinitcpio-openswap` | 0.1.0-3 | hibernate-from-encrypted-swap hook |

Three of the eight are the Calamares generation of the installer, which has been
replaced. Nothing in the current image needs any of them, which is why the ISO
does not depend on this repo at all today.

## Why it is switched off: the packages are not signed

This is the important finding and it is not a small one.

`dbupdate.sh` builds the database with `repo-add -s`. The `-s` flag signs **the
database**, not the packages in it. Inspecting the repo confirms it:

```console
$ gpg --list-packets x86_64/luminos-repository-db.sig
:signature packet: algo 1, keyid 070A4A036B2FE475
    version 4, created 1713996721       # 2024-04-24

$ ls x86_64/*.pkg.tar.zst.sig
ls: cannot access 'x86_64/*.pkg.tar.zst.sig': No such file or directory

$ tar xzOf x86_64/luminos-repository.db calamares-3.3.1-1/desc | grep PGPSIG
                                        # nothing
```

So: database signed, **zero packages signed, no `%PGPSIG%` fields**.

Under any `SigLevel` that actually verifies packages — including the
`Required DatabaseOptional` that both upstream `archiso` and LuminOS use —
pacman rejects every package in this repo. The only configuration that would
make it work is:

```ini
SigLevel = Optional TrustAll   # <- do not do this
```

`TrustAll` means pacman installs whatever the server hands it, without checking
who produced it. On a package repository this is a root-code-execution channel:
anyone who can modify the hosting (a compromised GitHub token, a hijacked Pages
deployment, a MITM on a user who somehow ends up on plain HTTP) gets to run
arbitrary code as root on every LuminOS machine that syncs. And it fails at the
worst possible moment — a user's **first install**, which is the one moment they
have no way to tell a broken distro from a malicious one.

So the repo stays out of `releng/pacman.conf`, and the entry in the live
`airootfs/etc/pacman.conf` is commented out with the correct `SigLevel` and a
pointer here.

The private half of key `070A4A036B2FE475` belongs to the original author. It is
not available to this project and must not be. Packages cannot simply be
re-signed with it.

## What has to happen to turn it on

Three things, all required:

### 1. A LuminOS repository signing key

A key whose **public** half ships in the image and whose **private** half signs
packages. This needs a custody decision before it is generated, because whoever
holds it can push root-level code to every LuminOS user:

- where the private key lives (Paperclip secret / hardware token / offline)
- who or what is allowed to sign a package
- what happens when it is rotated or compromised

That decision is escalated to Chief of Staff. It is not a technical blocker — it
is a "who gets to own this" blocker, and generating a distro signing key
unilaterally inside a build sandbox would be the wrong way to answer it.

### 2. Sign the packages, not just the database

`scripts/dbupdate.sh` in the repository has been rewritten to do this. The
mechanism:

```bash
# per package, a detached signature next to it
gpg --detach-sign --use-agent --no-armor --local-user "$LUMINOS_SIGNING_KEY" pkg.tar.zst
# then repo-add picks the .sig up and records %PGPSIG% in the database
repo-add -s -v -n -R luminos-repository.db.tar.gz *.pkg.tar.zst
```

Verify afterwards — `repo-add` succeeding is not evidence the packages are
signed, which is the exact mistake that produced the current state:

```bash
tar xzOf luminos-repository.db.tar.gz '*/desc' | grep -c PGPSIG   # must equal package count
```

### 3. A `luminos-keyring` package

This is how the public key becomes trusted without anyone running
`pacman-key --lsign-key` by hand. A keyring package drops the key into
`/usr/share/pacman/keyrings/`, and `pacman-init.service` (already enabled in this
profile) runs `pacman-key --init && pacman-key --populate` at every live boot,
which picks up every keyring installed in the image.

A skeleton `PKGBUILD` is in the repository under `keyring/`. Note it is
chicken-and-egg: `luminos-keyring` itself has to come from somewhere pacman
already trusts, so it is installed **from the image** (listed in
`packages.x86_64` once the repo is live), not fetched from the repo it
authenticates.

## Hosting

**No spend is needed.** Both viable options are $0, so this is a repo-admin
permission question rather than a budget one.

| Option | Cost | Notes |
|---|---|---|
| **GitHub Releases** (recommended) | $0 | 2 GB/asset, no bandwidth billing, and binaries stay out of git history. `Server = https://github.com/Lumin-OS/luminos-repository/releases/download/<tag>` |
| GitHub Pages | $0 | Simplest — the repo already stores packages in-tree, so Pages serves them as-is. But: 1 GB soft repo limit and 100 GB/month soft bandwidth limit, and every package version is kept in git history forever. The repo is ~37 MB today and would grow without bound. |
| Cloudflare R2 | $0 up to 10 GB | No egress fees. More moving parts, another account to own. |
| VPS | ~$5/month | Only worth it if LuminOS wants its own domain and mirror protocol. Not now. |

Recommendation: **GitHub Releases**, because storing every historical build of an
18 MB package in git is the failure mode Pages walks into, and Releases is free of
it at the same price.

Enabling either needs admin on the `Lumin-OS` org repo, which is a Chief of Staff
item.

## Does any of this block the ISO?

No. The Hyprland session is built entirely from official Arch repositories. The
repository matters for the **installer** (`dawn`, owned by Rhys) and for any
LuminOS-specific package that ships later. Turning it on is a one-line change in
`releng/airootfs/etc/pacman.conf` plus adding `luminos-keyring` to
`packages.x86_64`, once the three items above are done.
