#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Charge screen (the oakMOSS model), ported from TwigUI-Next's (spruceUI/twigUI-next,
# projects/twigUI/devices/RK3326S/packages/charge-mode). The initramfs runs it (local-bottom/darkmoss-charge;
# init-charge before systemd on units with no initramfs) with busybox only: battery level, dark after 30 s,
# any key wakes, power boots.
#   charge-mode.sh [FRAMES-DIR]   (default /root/usr/local/share/darkmoss-charge)
#   exit 0: not a charger power-on (no steady charger counts), or power key while lit: carry on booting
#   exit 2: charger gone for 3 s, power off (the caller unmounts and powers off)

FRAMES=${1:-/root/usr/local/share/darkmoss-charge}
FB=${CHARGE_MODE_FB:-/dev/fb0}
FBSYS=/sys/class/graphics/fb0
PS=/sys/class/power_supply
GOV=/sys/devices/system/cpu/cpufreq/policy0/scaling_governor
LOG=${CHARGE_MODE_LOG:-/tmp/charge-mode.log}
PRINTK=${CHARGE_MODE_PRINTK:-/proc/sys/kernel/printk}
DT=${CHARGE_MODE_DT:-/proc/device-tree/compatible}
BLANK_AFTER=30

log() { echo "$(cut -d' ' -f1 /proc/uptime) charge-mode: $*" >> "$LOG" 2>/dev/null; }

[ $(( $( { wc -c < "$LOG"; } 2>/dev/null || echo 0) )) -gt 65536 ] &&
    tail -n 200 "$LOG" > "$LOG.new" 2>/dev/null && mv "$LOG.new" "$LOG"

# The kernel's reboot-mode magic in PMU_GRF + 0x200: 0 on a cold boot; both U-Boots write BOOT_NORMAL
# back after reading it, so a warm reboot never reads 0.
case "$(tr '\000' ' ' < "$DT" 2>/dev/null)" in
    *rockchip,rk3566*|*rockchip,rk3568*) BOOT_MODE_REG=0xfdc20200 ;;
    *rockchip,rk3326*|*rockchip,px30*) BOOT_MODE_REG=0xff010200 ;;
    *) BOOT_MODE_REG="" ;;
esac

# Powered on by plugging in: the RK817 on-source (rk808 logs it; bit 6 plug-in, bit 7 power key)
# on a cold boot. Anything unread counts as a normal boot.
on=$(dmesg 2>/dev/null | sed -n 's/.*source: on=0x\([0-9a-fA-F][0-9a-fA-F]*\),.*/\1/p' | tail -n 1)
mode=""
[ -n "$BOOT_MODE_REG" ] && mode=$(devmem $BOOT_MODE_REG 32 2>/dev/null)
if [ -z "$on" ] || [ -z "$mode" ] || [ $((0x$on & 0xc0)) -ne $((0x40)) ] || [ $((mode)) -ne 0 ]; then
    log "on=0x${on:-?} boot-mode=${mode:-?}: not a charger power-on"
    exit 0
fi

# True while a supply reads online; SUPPLY is its name.
online() {
    for _o in $PS/*/online; do
        if [ "$(cat "$_o" 2>/dev/null)" = 1 ]; then
            _o=${_o%/online}; SUPPLY=${_o##*/}
            return 0
        fi
    done
    return 1
}

# A reset that bypasses Linux (reset key, watchdog) keeps on=0x40 and the register at 0, so a charger must
# also stay online for 3 s: after such a reset on battery the V10 reads one online until 4 s after start.
# 4 s offline, or 10 s without a steady one, boots: powering off here would turn the reset into a power-off.
n=0; up=0; down=0; SUPPLY=""
while :; do
    if online; then up=$((up + 1)); down=0; else down=$((down + 1)); up=0; fi
    [ "$up" -ge 12 ] && break
    n=$((n + 1))
    if [ "$down" -ge 16 ] || [ "$n" -ge 40 ]; then
        why="${SUPPLY:-no charger} online${SUPPLY:+ only briefly}"
        log "on=0x$on boot-mode=$mode, $why: not a charger power-on"
        exit 0
    fi
    usleep 250000
done
log "on=0x$on boot-mode=$mode, $SUPPLY online: charger power-on"

BAT=$PS/battery
for _p in $PS/*; do
    [ "$(cat "$_p/type" 2>/dev/null)" = Battery ] && { BAT=$_p; break; }
done
level() {
    c=$(cat $BAT/capacity 2>/dev/null)
    case "$c" in ''|*[!0-9]*) c=0 ;; esac
    echo "$c"
}

level_frame() {
    c=$(( ($(level) + 2) / 5 * 5 )); [ "$c" -gt 100 ] && c=100
    printf '%s/level-%03d.raw.gz' "$FRAMES" "$c"
}

# The frames are fb0's own bytes at its size (make-frames.py), written at the panned offset. A unit
# with two panels has one set per fb0 width (w<width>/).
_w=$(cut -d, -f1 $FBSYS/virtual_size 2>/dev/null)
[ -n "$_w" ] && [ -f "$FRAMES/w$_w/fb" ] && FRAMES=$FRAMES/w$_w
read -r FW _ 2>/dev/null < "$FRAMES/fb"
STRIDE=$(cat $FBSYS/stride 2>/dev/null)
show() {
    _y=$(cut -d, -f2 $FBSYS/pan 2>/dev/null)
    gunzip -c "$1" | dd of="$FB" bs="$STRIDE" seek="${_y:-0}" conv=notrunc 2>/dev/null
}

if [ ! -f "$FRAMES/level-100.raw.gz" ] || [ -z "$FW" ] || [ "$(cat $FBSYS/bits_per_pixel 2>/dev/null)" != 32 ] ||
   [ "$STRIDE" != $((FW * 4)) ] || [ "$(cut -d, -f1 $FBSYS/virtual_size 2>/dev/null)" != "$FW" ]; then
    log "no frames for fb0 ($(cat $FBSYS/virtual_size 2>/dev/null), stride ${STRIDE:-?}) in $FRAMES, booting"
    exit 0
fi

gov=$(cat "$GOV" 2>/dev/null)
echo powersave > "$GOV" 2>/dev/null
# The boot console (tty1) echoes keys and repaints its text on unblank: run on an empty VT with
# console messages muted, and give both back before leaving (console_back).
loglevel=$(cut -f1 "$PRINTK" 2>/dev/null)
echo 1 > "$PRINTK" 2>/dev/null
chvt 2 2>/dev/null
console_back() {
    chvt 1 2>/dev/null
    [ -n "$loglevel" ] && echo "$loglevel" > "$PRINTK" 2>/dev/null
}
echo 0 > "$FBSYS/blank" 2>/dev/null
frame=$(level_frame); show "$frame"

# The power key by name (rk8xx_pwrkey on 4.4, "rk805 pwrkey" on 5.10); every other key-only node
# wakes. Joypads with sticks are left out: their axis events are more than the shell can read.
pek=""; pads=""; n=0
while :; do
    pek=""; pads=""
    for d in /sys/class/input/event*; do
        [ -e "$d" ] || continue
        case "$(cat "$d/device/name" 2>/dev/null)" in
            *pwrkey*) pek=/dev/input/${d##*/}; continue ;;
        esac
        k=$(cat "$d/device/capabilities/key" 2>/dev/null)
        [ -n "$k" ] && [ "$k" != 0 ] && [ "$(cat "$d/device/capabilities/abs" 2>/dev/null)" = 0 ] &&
            pads="$pads /dev/input/${d##*/}"
    done
    [ -n "$pek" ] && break
    [ "$n" -ge 20 ] && break
    usleep 250000; n=$((n + 1))
done
log "charging at $(level)% (governor $gov -> powersave), power key ${pek:-none}, pads${pads:- none}"
# Without a power key nothing could boot it but unplugging, which powers off: boot now.
if [ -z "$pek" ]; then
    log "no power key; booting"
    console_back
    [ -f "$FRAMES/booting.raw.gz" ] && show "$FRAMES/booting.raw.gz"
    [ -n "$gov" ] && echo "$gov" > "$GOV" 2>/dev/null
    exit 0
fi

# A reader per node appends the raw 24-byte input_events to a file, so a press is told from
# its release and none is missed between ticks.
TMP=${CHARGE_MODE_TMP:-/tmp}
PEK_LOG=$TMP/charge-pek; PAD_LOG=$TMP/charge-pad
: > "$PEK_LOG"; : > "$PAD_LOG"
pids=""
[ -n "$pek" ] && { cat "$pek" >> "$PEK_LOG" & pids="$pids $!"; }
for p in $pads; do cat "$p" >> "$PAD_LOG" & pids="$pids $!"; done
pek_off=0; pad_off=0

# key_down FILE OFFSET: true if a whole event after OFFSET is a key going down (type EV_KEY 1,
# value 1); NEXT is the new offset. The type, code and value bytes (16..23 of a 64-bit
# input_event) go through tr: 00 -> z, 01 -> o, then a pattern match.
key_down() {
    _sz=$(( $(wc -c < "$1") )); _o=$2; _d=1
    while [ $((_o + 24)) -le "$_sz" ]; do
        _e=$(dd if="$1" bs=1 skip=$((_o + 16)) count=8 2>/dev/null | tr '\000\001' 'zo')
        case "$_e" in oz??ozzz) _d=0 ;; esac
        _o=$((_o + 24))
    done
    NEXT=$_o
    return $_d
}

stop_readers() {
    for p in $pids; do kill "$p" 2>/dev/null; done
    rm -f "$PEK_LOG" "$PAD_LOG"
}

# 4 ticks a second. The charger counts as gone only after 3 s offline (oakMOSS saw a fresh
# charger read offline once on a flat cell).
TICKS=$((BLANK_AFTER * 4)); lit=$TICKS; offline=0
while :; do
    if online; then offline=0; else offline=$((offline + 1)); fi
    if [ "$offline" -ge 12 ]; then
        log "charger removed at $(level)%; powering off"
        stop_readers; console_back
        exit 2
    fi
    power=1; other=1
    key_down "$PEK_LOG" "$pek_off" && power=0; pek_off=$NEXT
    key_down "$PAD_LOG" "$pad_off" && other=0; pad_off=$NEXT
    [ "$power" = 0 ] && [ "$lit" -gt 0 ] && break
    if [ "$power" = 0 ] || [ "$other" = 0 ]; then
        if [ "$lit" -eq 0 ]; then
            echo 0 > "$FBSYS/blank" 2>/dev/null
            frame=$(level_frame); show "$frame"
            log "woken at $(level)%"
        fi
        lit=$TICKS
    fi
    if [ "$lit" -gt 0 ]; then
        new=$(level_frame)
        [ "$new" != "$frame" ] && { frame=$new; show "$frame"; }
        lit=$((lit - 1))
        [ "$lit" -eq 0 ] && echo 4 > "$FBSYS/blank" 2>/dev/null
    fi
    usleep 250000
done

stop_readers
log "power key at $(level)%; booting"
console_back
echo 0 > "$FBSYS/blank" 2>/dev/null
# The boot logo until bootlogo.py or the frontend draws.
[ -f "$FRAMES/booting.raw.gz" ] && show "$FRAMES/booting.raw.gz"
[ -n "$gov" ] && echo "$gov" > "$GOV" 2>/dev/null
exit 0
