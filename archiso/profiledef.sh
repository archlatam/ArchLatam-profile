#!/usr/bin/env bash

iso_name="Core"
iso_label="Core_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Core GNU-Linux <https://github.com/archlatam>"
iso_application="Core Linux ISO"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
## Boot modes: BIOS legacy + UEFI (GRUB)
bootmodes=('bios.syslinux' 'uefi.grub')
arch="x86_64"
pacman_conf="pacman.conf"
## Kernel parameters (sustituidos en los .cfg como %KERNEL_PARAMS%)
kernel_params_x86_64="quiet splash"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-b' '1M')
# bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/etc/polkit-1/rules.d"]="0:0:750"
  ["/etc/sudoers.d"]="0:0:750"
  ["/etc/sudoers.d/g_wheel"]="0:0:440"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/usr/local/bin/pkexec-wrapper"]="0:0:755"
  ["/usr/local/bin/archlatam-installer"]="0:0:755"
  ["/usr/local/bin/Installation_guide"]="0:0:755"
  ["/usr/local/bin/livecd-sound"]="0:0:755"
  ["/usr/local/bin/customize-profile.sh"]="0:0:755"
  ["/etc/mkinitcpio.d/linux.preset"]="0:0:644"  
)
