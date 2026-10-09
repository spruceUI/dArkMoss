#!/bin/sh
# Mount spruce at /mnt/SDCARD, where spruce expects to find itself. The card in
# the other slot (TF2, partition 1) wins; failing that, a FAT partition on the
# boot card (TF1, the SPRUCEOS partition firstboot made). No spruce after one
# retry: say so and power off.
TTY=/dev/tty1

say() {
  printf '\033[2J\033[H\n\n  %s\n' "$1" > "$TTY" 2>/dev/null
}

candidates() {
  root_disk=$(lsblk -no PKNAME "$(findmnt -no SOURCE / | sed 's/\[.*//')" 2>/dev/null)
  boot_dev=$(findmnt -no SOURCE /boot 2>/dev/null)
  for dev in /sys/block/mmcblk*; do
    disk=${dev##*/}
    [ "$disk" != "$root_disk" ] || continue
    [ "$(cat "$dev/device/type" 2>/dev/null)" = SD ] || continue
    [ -b "/dev/${disk}p1" ] && echo "/dev/${disk}p1"
  done
  lsblk -rno PATH,FSTYPE "/dev/$root_disk" 2>/dev/null | while read -r path fstype; do
    [ "$path" != "$boot_dev" ] || continue
    case "$fstype" in vfat|exfat) echo "$path" ;; esac
  done
}

mount_spruce() {
  mountpoint -q /mnt/SDCARD && [ -f /mnt/SDCARD/spruce/scripts/runtime.sh ] && return 0
  for DEV in $(candidates); do
    mount -o rw,noatime,umask=0000 "$DEV" /mnt/SDCARD 2>/dev/null || continue
    [ -f /mnt/SDCARD/spruce/scripts/runtime.sh ] && return 0
    umount /mnt/SDCARD
  done
  return 1
}

mkdir -p /mnt/SDCARD
mount_spruce && exit 0

say "Looking for spruce card.........."
sleep 5
if mount_spruce; then
  printf '\033[2J\033[H' > "$TTY" 2>/dev/null
  exit 0
fi

say "spruce card not found, shutting down"
echo "spruce card not found, powering off" >&2
sleep 3
systemctl poweroff
sleep 60
exit 1
