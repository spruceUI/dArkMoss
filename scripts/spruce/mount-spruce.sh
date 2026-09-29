#!/bin/sh
# Mount the spruce card at /mnt/SDCARD, where spruce expects to find itself.
# The spruce card is whatever SD card is in the other slot: the first FAT or
# exFAT partition on an SD card that is not the boot card. Its label does not
# matter. No spruce after one retry: say so and power off.
TTY=/dev/tty1

say() {
  printf '\033[2J\033[H\n\n  %s\n' "$1" > "$TTY" 2>/dev/null
}

find_spruce_card() {
  root_disk=$(lsblk -no PKNAME "$(findmnt -no SOURCE / | sed 's/\[.*//')" 2>/dev/null)
  for dev in /sys/block/mmcblk*; do
    disk=${dev##*/}
    [ "$disk" != "$root_disk" ] || continue
    [ "$(cat "$dev/device/type" 2>/dev/null)" = SD ] || continue
    lsblk -rno NAME,TYPE,FSTYPE "/dev/$disk" | while read -r name type fstype; do
      [ "$type" = part ] || continue
      case "$fstype" in
        vfat|exfat) echo "/dev/$name"; break ;;
      esac
    done
  done | head -n 1
}

mount_spruce() {
  mountpoint -q /mnt/SDCARD && [ -f /mnt/SDCARD/spruce/scripts/runtime.sh ] && return 0
  DEV=$(find_spruce_card)
  [ -n "$DEV" ] || return 1
  mountpoint -q /mnt/SDCARD || mount -o rw,noatime,umask=0000 "$DEV" /mnt/SDCARD || return 1
  [ -f /mnt/SDCARD/spruce/scripts/runtime.sh ] && return 0
  umount /mnt/SDCARD
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
echo "spruce card not found (${DEV:-no SD card besides the boot card}), powering off" >&2
sleep 3
systemctl poweroff
sleep 60
exit 1
