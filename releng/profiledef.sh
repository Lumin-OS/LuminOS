#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="luminos"
iso_label="LuminOS_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="LuminOS <TODO: Get domain>"
iso_application="LuminOS LiveCD"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
# Dawn's offline install reads the image from
# /run/archiso/bootmnt/arch/x86_64/airootfs.sfs (luminos-dawn's
# installer.toml), so this stays "arch".
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux.mbr' 'bios.syslinux.eltorito'
           'uefi-ia32.grub.esp' 'uefi-x64.grub.esp'
           'uefi-ia32.grub.eltorito' 'uefi-x64.grub.eltorito')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  # The live user's home. mkarchiso copies airootfs as root, so every
  # file in it needs an entry here, or the live user can't write to it.
  ["/home/luminos"]="1000:1000:700"
  ["/home/luminos/.config"]="1000:1000:755"
  ["/home/luminos/.config/hypr"]="1000:1000:755"
  ["/home/luminos/.config/hypr/hyprland.lua"]="1000:1000:644"
  ["/home/luminos/.zlogin"]="1000:1000:644"
  ["/home/luminos/.zprofile"]="1000:1000:644"
)
