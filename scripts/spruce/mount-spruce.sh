#!/bin/sh
# Mount spruce at /mnt/SDCARD, where spruce expects to find itself. spruce is on
# partition 1 of the card in the other slot (TF2), or on a FAT/exFAT partition
# of the boot card (TF1, the SPRUCEOS partition firstboot made). With both, ask
# which; the last answer is the default. No spruce after one retry: say so and
# power off.
TTY=/dev/tty1
CHOICE=/boot/spruce-card
PROBE=/run/spruce-probe

say() {
  printf '\033[2J\033[H\n\n  %s\n' "$1" > "$TTY" 2>/dev/null
}

candidates() {
  root_disk=$(lsblk -no PKNAME "$(findmnt -no SOURCE / | sed 's/\[.*//')" 2>/dev/null)
  boot_dev=$(findmnt -no SOURCE /boot 2>/dev/null)
  for dev in /sys/block/mmcblk*; do
    disk=${dev##*/}
    [ "$(cat "$dev/device/type" 2>/dev/null)" = SD ] || continue
    if [ "$disk" = "$root_disk" ]; then
      lsblk -rno PATH,FSTYPE "/dev/$disk" | while read -r path fstype; do
        [ "$path" != "$boot_dev" ] || continue
        case "$fstype" in vfat|exfat) echo "TF1 $path" ;; esac
      done
    elif [ -b "/dev/${disk}p1" ]; then
      echo "TF2 /dev/${disk}p1"
    fi
  done
}

# "<slot> <device> <spruce version>" for each partition that holds spruce.
find_spruce() {
  mkdir -p "$PROBE"
  candidates | while read -r slot path; do
    mount -o ro "$path" "$PROBE" 2>/dev/null || continue
    if [ -f "$PROBE/spruce/scripts/runtime.sh" ]; then
      echo "$slot $path $(head -n 1 "$PROBE/spruce/spruce" 2>/dev/null)"
    fi
    umount "$PROBE"
  done
}

choose() {
  last=$(cat "$CHOICE" 2>/dev/null)
  set --
  while read -r slot path version; do
    set -- "$@" "$slot" "spruce ${version:-(unknown version)}"
  done <<EOF
$found
EOF
  export TERM=linux
  /opt/inttools/gptokeyb -1 dialog -c /opt/inttools/keys.gptk > /dev/null 2>&1 &
  pad=$!
  pick=$(dialog --output-fd 3 --no-cancel --timeout 10 --default-item "${last:-TF2}" \
    --title "spruce" --menu "Boot spruce from:" 10 40 2 "$@" 3>&1 > "$TTY" < "$TTY")
  kill "$pad" 2>/dev/null
  printf '\033[2J\033[H' > "$TTY" 2>/dev/null
  [ -n "$pick" ] || pick=${last:-TF2}
  echo "$found" | grep -q "^$pick " || pick=$(echo "$found" | head -n 1 | cut -d ' ' -f 1)
  echo "$pick" > "$CHOICE"
  echo "$found" | awk -v s="$pick" '$1 == s { print $2; exit }'
}

mount_spruce() {
  mountpoint -q /mnt/SDCARD && [ -f /mnt/SDCARD/spruce/scripts/runtime.sh ] && return 0
  found=$(find_spruce)
  [ -n "$found" ] || return 1
  if [ "$(echo "$found" | wc -l)" -gt 1 ]; then
    DEV=$(choose)
  else
    DEV=$(echo "$found" | cut -d ' ' -f 2)
  fi
  mount -o rw,noatime,umask=0000 "$DEV" /mnt/SDCARD
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
