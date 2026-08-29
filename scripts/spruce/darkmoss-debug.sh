#!/bin/sh
# Export readable logs to the boot partition, where a PC can get at them.
#
# Off unless /boot/darkmoss-debug exists. /boot is the FAT partition labelled
# dArkMoss - the only thing on TF1 a Windows or Mac machine can read - so
# turning this on is "create an empty file on the card", and reading the result
# back is "look in /boot/logs". No SSH, no btrfs driver, no second device.
#
# The journal itself is always persistent (journald.conf, 64M cap); this only
# makes it legible off the card. Keeping the /boot writes behind a flag is
# deliberate: an unclean poweroff can dirty that FAT partition, and unlike a
# dirty data partition a dirty /boot is a device that does not boot. Users who
# have not asked for logs never take that risk.
#
# To add a collector, add a line in the block marked below. One file each, keep
# it cheap and non-blocking - this runs on every boot the flag is set.

FLAG=/boot/darkmoss-debug
LOGDIR=/boot/logs
KEEP=5

[ -e "$FLAG" ] || exit 0
mountpoint -q /boot || exit 0

STAMP=$(date +%Y%m%d-%H%M%S 2>/dev/null) || STAMP=unknown
OUT="$LOGDIR/$STAMP"
mkdir -p "$OUT" || exit 0

# The previous boot is usually the interesting one: you reproduce the fault,
# power cycle, and read it here. -b 0 covers anything that has already gone
# wrong this boot.
journalctl -b -1 --no-pager > "$OUT/previous-boot.log" 2>/dev/null
journalctl -b 0 --no-pager  > "$OUT/this-boot.log"     2>/dev/null
dmesg                       > "$OUT/dmesg.log"         2>/dev/null

{
    echo "date:    $(date 2>/dev/null)"
    echo "kernel:  $(uname -a 2>/dev/null)"
    echo "uptime:  $(uptime 2>/dev/null)"
    echo
    echo "--- mounts"
    mount
    echo
    echo "--- disk"
    df -h
    echo
    echo "--- failed units"
    systemctl --failed --no-pager 2>/dev/null
} > "$OUT/system.txt" 2>/dev/null

# spruce keeps its own log on TF2. Copy it if the card is up by the time we run.
if [ -f /mnt/SDCARD/Saves/spruce/spruce.log ]; then
    cp -f /mnt/SDCARD/Saves/spruce/spruce.log "$OUT/spruce.log" 2>/dev/null
fi

# --- add further collectors here -------------------------------------------

# Keep the newest $KEEP runs. /boot is 104MB and a dirty one is a brick, so
# this is not optional housekeeping.
ls -1d "$LOGDIR"/*/ 2>/dev/null | sort | head -n "-$KEEP" | while read -r old; do
    rm -rf "$old"
done

sync
