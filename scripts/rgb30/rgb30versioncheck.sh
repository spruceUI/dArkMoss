#!/bin/bash

# RGB20SX: an RGB30 with an RTL8723DS radio (SDIO 024C:D723). Its dtb replaces
# the RGB30 one under the same name, so extlinux needs no change, and the v1/v2
# check below does not apply. Takes effect on the next boot, and re-applies
# if an update puts the RGB30 dtb back.
if grep -qs "SDIO_ID=024C:D723" /sys/bus/sdio/devices/*/uevent; then
  if ! cmp -s /usr/local/bin/rgb30dtbs/rk3566-rgb20sx.dtb /boot/rk3566-rgb30.dtb; then
    sudo cp -f /usr/local/bin/rgb30dtbs/rk3566-rgb20sx.dtb /boot/rk3566-rgb30.dtb
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