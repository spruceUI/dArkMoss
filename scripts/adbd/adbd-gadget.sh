#!/bin/bash
# USB gadget for adbd. Debian's adbd needs no authorization and falls back to
# TCP 5555 when /dev/usb-ffs/adb/ep0 is missing, so every step that could leave
# it without FunctionFS fails instead of carrying on.

G=/sys/kernel/config/usb_gadget/adb
FFS=/dev/usb-ffs/adb

find_udc() {
    for _ in $(seq 20); do
        UDC="$(ls /sys/class/udc 2>/dev/null | head -1)"
        [ -n "$UDC" ] && return 0
        sleep 0.5
    done
    return 1
}

# The OTG controller doubles as a host; leave it alone while something is on its bus.
host_in_use() {
    for hub in /sys/bus/usb/devices/usb*; do
        [ "$(cat "$hub/serial" 2>/dev/null)" = "$UDC" ] || continue
        for dev in "$hub"/*-*; do
            case "$dev" in *:*) continue ;; esac
            [ -e "$dev" ] && return 0
        done
    done
    return 1
}

case "$1" in
    check)
        modprobe -q libcomposite
        modprobe -q usb_f_fs
        modprobe -q dwc2
        find_udc || exit 1
        ! host_in_use
        ;;
    setup)
        find_udc || exit 1
        mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config || exit 1
        mkdir -p "$G/strings/0x409" "$G/configs/c.1/strings/0x409" "$G/functions/ffs.adb" || exit 1
        echo 0x18d1 > "$G/idVendor"
        echo 0x4ee7 > "$G/idProduct"
        echo dArkMoss > "$G/strings/0x409/manufacturer"
        tr -d '\0' < /proc/device-tree/model > "$G/strings/0x409/product"
        sha256sum < /etc/machine-id 2>/dev/null | cut -c1-16 > "$G/strings/0x409/serialnumber"
        echo adb > "$G/configs/c.1/strings/0x409/configuration"
        [ -L "$G/configs/c.1/ffs.adb" ] || ln -s "$G/functions/ffs.adb" "$G/configs/c.1/" || exit 1
        mkdir -p "$FFS"
        mountpoint -q "$FFS" || mount -t functionfs adb "$FFS" || exit 1
        [ -e "$FFS/ep0" ]
        ;;
    activate)
        find_udc && echo "$UDC" > "$G/UDC"
        ;;
    reset)
        [ -e "$G/UDC" ] && echo "" > "$G/UDC"
        mountpoint -q "$FFS" && umount "$FFS"
        rm -f "$G/configs/c.1/ffs.adb"
        rmdir "$G/configs/c.1/strings/0x409" "$G/configs/c.1" "$G/functions/ffs.adb" \
            "$G/strings/0x409" "$G" 2>/dev/null
        exit 0
        ;;
    *)
        echo "Usage: $0 check|setup|activate|reset" >&2
        exit 1
        ;;
esac
