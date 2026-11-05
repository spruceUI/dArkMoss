# Sourced by build_kernel.sh and build_kernel-rk3566.sh before update-initramfs: the charge screen
# (charge-mode.sh, its initramfs hook and the unit's frames from make-frames.py) for the units that opt in.
# Those units also turn U-Boot's own charge animation off (rockchip,uboot-charge-on 0 in BOOT's uboot.dtb
# or the resource's rk-kernel.dtb), so the two do not run one after the other.
case "$UNIT" in
  g350|xumini) CHARGE_MODE=y ;;
  *) CHARGE_MODE=n ;;
esac

if [ "$CHARGE_MODE" == "y" ]; then
  sudo install -D -m 0755 scripts/charge-mode/darkmoss-charge \
    Arkbuild/etc/initramfs-tools/scripts/local-bottom/darkmoss-charge
  sudo install -D -m 0755 scripts/charge-mode/charge-mode.sh Arkbuild/usr/local/lib/darkmoss-charge/charge-mode.sh
  sudo rm -rf Arkbuild/usr/local/share/darkmoss-charge
  sudo mkdir -p Arkbuild/usr/local/share/darkmoss-charge
  sudo cp scripts/charge-mode/frames/${UNIT}/* Arkbuild/usr/local/share/darkmoss-charge/
  if ! command -v fdtput &> /dev/null; then
    sudo apt -y update
    sudo apt -y install device-tree-compiler
  fi
else
  # A cached chroot may carry it from an opted-in unit.
  sudo rm -f Arkbuild/etc/initramfs-tools/scripts/local-bottom/darkmoss-charge
fi
