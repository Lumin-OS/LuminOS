#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="luminos"
iso_label="LuminOS_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="LuminOS <https://github.com/Lumin-OS>"
iso_application="LuminOS LiveCD"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
# archiso 90 renamed every boot mode this profile used. The old names still
# work but emit deprecation warnings, and the six old entries collapse into
# exactly these two:
#   bios.syslinux.mbr + bios.syslinux.eltorito          -> bios.syslinux
#   uefi-{ia32,x64}.grub.{esp,eltorito}                 -> uefi.grub
# 'uefi.grub' covers IA32 and x64, and emits both the ESP and the El Torito
# image, so BIOS and UEFI are both still covered.
#
# grub (not systemd-boot, which is what upstream archiso now defaults to)
# because LuminOS's branded menu lives in releng/grub/grub.cfg and grub is what
# renders it. Note archiso rejects combining 'uefi.grub' with
# 'uefi.systemd-boot' — it is one or the other.
bootmodes=('bios.syslinux' 'uefi.grub')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/root/.gnupg"]="0:0:700"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/usr/local/bin/Installation_guide"]="0:0:755"
  ["/usr/local/bin/livecd-sound"]="0:0:755"
  # Without this, everything under airootfs/home/luminos lands root-owned and
  # the autologin session cannot write its own state — zsh cannot create its
  # history and Hyprland cannot create its runtime dirs, so the session dies
  # immediately after the compositor starts. archiso does not infer ownership
  # from /etc/passwd; it has to be declared here.
  ["/home/luminos"]="1000:1000:755"
  ["/home/luminos/.zprofile"]="1000:1000:644"
  ["/home/luminos/.config"]="1000:1000:755"
)
