# Sourced by build_kernel.sh and build_kernel-rk3566.sh before update-initramfs: the charge screen
# (charge-mode.sh, its initramfs hook and the unit's frames from make-frames.py) for the units that opt in.
# Those units also turn U-Boot's own charge animation off (rockchip,uboot-charge-on 0 in the U-Boot dtb on
# BOOT or the resource's rk-kernel.dtb), so the two do not run one after the other.
# V10 boots with no initramfs: init-charge runs it before systemd instead (finishing_touches.sh's init=).
# $UNIT as build_<unit>.sh exports it (the RG353M's is 353m); frames/ folders use the same names.
# Not the G350 or the A10 Mini: no charge screen at plug-in, installed or not. Not the RG353M: no unit
# to test it on. Their frames stay. Not the E5 Plus: it has its own (scripts/e5plus/e5plus-offcharge.py).
case "$UNIT" in
  xumini|v10|miniloong|rgb30) CHARGE_MODE=y ;;
  *) CHARGE_MODE=n ;;
esac

# A cached chroot may carry these from an earlier build.
sudo rm -f Arkbuild/etc/initramfs-tools/scripts/local-bottom/darkmoss-charge
sudo rm -rf Arkbuild/usr/local/lib/darkmoss-charge Arkbuild/usr/local/share/darkmoss-charge
if [ "$CHARGE_MODE" == "y" ]; then
  sudo install -D -m 0755 scripts/charge-mode/charge-mode.sh Arkbuild/usr/local/lib/darkmoss-charge/charge-mode.sh
  if [ "$UNIT" == "v10" ]; then
    # PID 1 by its #!/bin/busybox: without busybox the kernel would panic at init=.
    if [ ! -x Arkbuild/bin/busybox ]; then
      echo "ERROR: charge mode: Arkbuild/bin/busybox is missing; init-charge needs it."
      exit 1
    fi
    sudo install -D -m 0755 scripts/charge-mode/init-charge Arkbuild/usr/local/lib/darkmoss-charge/init-charge
  else
    sudo install -D -m 0755 scripts/charge-mode/darkmoss-charge \
      Arkbuild/etc/initramfs-tools/scripts/local-bottom/darkmoss-charge
  fi
  sudo mkdir -p Arkbuild/usr/local/share/darkmoss-charge
  sudo cp -r scripts/charge-mode/frames/${UNIT}/. Arkbuild/usr/local/share/darkmoss-charge/
  if ! command -v fdtput &> /dev/null; then
    sudo apt -y update
    sudo apt -y install device-tree-compiler
  fi
fi

# Every device path this file can install, any unit's frames layout. build_update.sh puts them in
# remove.list on a unit left out, so an update clears what an earlier build installed.
charge_mode_paths() {
  printf '%s\n' /etc/initramfs-tools/scripts/local-bottom/darkmoss-charge \
    /usr/local/lib/darkmoss-charge/charge-mode.sh /usr/local/lib/darkmoss-charge/init-charge
  (cd scripts/charge-mode/frames && find . -mindepth 2 \( -type f -o -type l \)) |
    sed -E 's#^\./[^/]+/#/usr/local/share/darkmoss-charge/#' | sort -u
}
