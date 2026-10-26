#!/bin/sh
# GKD Pixel 2: the rk817 card's extcon cable "HEADPHONE" picks the codec's Playback Path
# (the 5.10 codec does not switch on its own). Run by 99-pixel2-jack.rules and pixel2-jack.service.
for cable in /sys/class/extcon/extcon*/cable.*; do
	[ "$(cat "$cable/name" 2>/dev/null)" = "HEADPHONE" ] || continue
	if [ "$(cat "$cable/state" 2>/dev/null)" = "1" ]; then path=HP; else path=SPK; fi
	exec amixer -q -c 0 cset name='Playback Path' "$path"
done
