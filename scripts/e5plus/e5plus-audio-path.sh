#!/bin/sh
# GameMT E5 Plus: route the rk817 codec to the headphones while the jack is in
# and to the speaker otherwise. Run by udev on every rk-headset extcon change
# (99-e5plus-headphones.rules) and at boot right after spktoggle.sh (cron),
# whose SPK_HP default it overrides.
#
# Needed because nothing else follows the jack here: rk_headset reports it on
# the extcon but the codec's own jack hook (rk817_headset_detect) is compiled
# out, and spruce only re-applies the path when the volume changes - which the
# E5 Plus's volume keys cannot do.
hp=0
for x in /sys/class/extcon/*; do
    [ "$(cat "$x/name" 2>/dev/null)" = "rk-headset" ] || continue
    grep -q 'HEADPHONE=1' "$x/state" 2>/dev/null && hp=1
done
if [ "$hp" = 1 ]; then path=HP; else path=SPK; fi
amixer -q -c 0 cset name='Playback Path' "$path" 2>/dev/null
logger -t e5plus-audio-path "headphones=$hp, Playback Path=$path" 2>/dev/null
exit 0
