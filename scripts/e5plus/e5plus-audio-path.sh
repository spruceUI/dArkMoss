#!/bin/sh
# GameMT E5 Plus: route the rk817 codec to the headphones while the jack is in
# and to the speaker otherwise.
#
#   e5plus-audio-path.sh          apply once (exit 0)
#   e5plus-audio-path.sh watch    keep it applied (e5plus-jackd.service)
#
# Why polling: the jack switch (GPIO4_C6, high = plugged) is right, but
# rk_headset reads it only on an edge, re-reads it 100 ms later and gives up
# without re-arming when the two disagree - a plug bounces, so it misses
# insertions and its extcon stays stale. The pin's live level does not lie.
# Re-applying on every pass also undoes spktoggle.sh's SPK_HP at boot and
# anything else that moves the path.

headphones_in() {
    _l="$(grep 'headset_gpio' /sys/kernel/debug/gpio 2>/dev/null)"
    if [ -n "$_l" ]; then
        case "$_l" in *" hi"*) return 0 ;; *) return 1 ;; esac
    fi
    # No debugfs: fall back to the (less reliable) extcon.
    for x in /sys/class/extcon/*; do
        [ "$(cat "$x/name" 2>/dev/null)" = "rk-headset" ] || continue
        grep -q 'HEADPHONE=1' "$x/state" 2>/dev/null && return 0
    done
    return 1
}

apply() {
    if headphones_in; then want=HP; else want=SPK; fi
    # Enum item index: OFF RCV SPK HP ... -> SPK=2, HP=3.
    case "$want" in SPK) idx=2 ;; HP) idx=3 ;; esac
    cur="$(amixer -c 0 cget name='Playback Path' 2>/dev/null | sed -n 's/.*: values=//p')"
    if [ "$cur" != "$idx" ]; then
        amixer -q -c 0 cset name='Playback Path' "$want" 2>/dev/null &&
            logger -t e5plus-audio-path "Playback Path $cur -> $want" 2>/dev/null
    fi
}

if [ "$1" = "watch" ]; then
    while :; do apply; sleep 1; done
fi
apply
exit 0
