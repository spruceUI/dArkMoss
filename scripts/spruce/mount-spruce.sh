#!/bin/sh
# Wait for and mount the spruce card (TF2, a FAT partition labelled SPRUCEOS)
# at /mnt/SDCARD, where spruce expects to find itself.
#
# Poll for the card rather than racing it: on the RGB30 the second SD can
# enumerate a beat after userspace is up, and mounting too early was exactly
# what broke the MossySpruce boot. 30s cap, then fail and let systemd retry.
mkdir -p /mnt/SDCARD
i=0
while [ "$i" -lt 30 ]; do
  DEV=$(blkid -L SPRUCEOS 2>/dev/null)
  [ -n "$DEV" ] && break
  i=$((i + 1))
  sleep 1
done
if [ -z "$DEV" ]; then
  echo "spruce card (label SPRUCEOS) not found after 30s" >&2
  exit 1
fi
if ! mountpoint -q /mnt/SDCARD; then
  mount -o rw,noatime,umask=0000 "$DEV" /mnt/SDCARD
fi
