#!/bin/bash

# RGB20SX: an RGB30 with an RTL8723DS radio (SDIO 024C:D723). Its dtb replaces
# the RGB30 one under the same name, so extlinux needs no change. Like the RGB30
# it comes with either CPU regulator, so it has a dtb per regulator: pick the
# one matching the dtb that booted if vdd_cpu came up, else the other one.
# Takes effect on the next boot, and re-applies if an update puts the RGB30 dtb
# back.
if grep -qs "SDIO_ID=024C:D723" /sys/bus/sdio/devices/*/uevent; then
  DTBS=/usr/local/bin/rgb30dtbs
  BOOT_DTB=/boot/rk3566-rgb30.dtb
  booted=v1
  if cmp -s $DTBS/rk3566-rgb20sx.dtb.v2 $BOOT_DTB || cmp -s $DTBS/rk3566-rgb30.dtb.v2 $BOOT_DTB; then
    booted=v2
  fi
  want=$booted
  if test -z "$(dmesg | grep vdd_cpu | tr -d '\0')"; then
    [ "$booted" = v1 ] && want=v2 || want=v1
  fi
  target=$DTBS/rk3566-rgb20sx.dtb
  [ "$want" = v2 ] && target=$DTBS/rk3566-rgb20sx.dtb.v2
  if ! cmp -s $target $BOOT_DTB; then
    sudo cp -f $target $BOOT_DTB
  fi
  exit 0
fi

if test -z "$(dmesg | grep vdd_cpu | tr -d '\0')"
then
  if [ ! -f "/home/ark/.config/.V2DTBLOADED" ]; then
    sudo cp -f /usr/local/bin/rgb30dtbs/rk3566-rgb30.dtb.v2 /boot/rk3566-rgb30.dtb
    touch /home/ark/.config/.V2DTBLOADED
  else
    sudo cp -f /usr/local/bin/rgb30dtbs/rk3566-rgb30.dtb.v1 /boot/rk3566-rgb30.dtb
    rm -f /home/ark/.config/.V2DTBLOADED
  fi
fi