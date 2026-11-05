# Sourced by build_kernel.sh and build_kernel-rk3566.sh before update-initramfs: the charge screen
# (charge-mode.sh, its initramfs hook and the unit's frames from make-frames.py) for the units that opt in.
# Those units also turn U-Boot's own charge animation off (rockchip,uboot-charge-on 0 in the U-Boot dtb on
# BOOT or the resource's rk-kernel.dtb), so the two do not run one after the other.
# V10 boots with no initramfs: init-charge runs it before systemd instead (finishing_touches.sh's init=).
case "$UNIT" in
  g350|xumini|v10|a10mini|miniloong|rgb30|rg353m) CHARGE_MODE=y ;;
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
