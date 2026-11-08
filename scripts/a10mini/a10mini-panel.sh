#!/bin/sh
# The A10 Mini image boots the V4 too; boot.ini loads the V4's dtb ("... V4") there.
# Install the SDL builds and boot logo for the panel this boot found. Every boot,
# because a card can move between the two.

SHARE=/usr/local/share/a10mini

if grep -qas "V4" /proc/device-tree/model; then
    panel=v4
else
    panel=a10
fi

install_if_different() {
    [ -f "$1" ] && [ -f "$2" ] || return 0
    cmp -s "$1" "$2" && return 0
    cp -f "$1" "$2.new" && mv -f "$2.new" "$2"
}

install_if_different "$SHARE/sdl64-$panel" "$(readlink -f /usr/lib/aarch64-linux-gnu/libSDL2.so)"
install_if_different "$SHARE/sdl32-$panel" "$(readlink -f /usr/lib/arm-linux-gnueabihf/libSDL2.so)"
install_if_different "$SHARE/logo-$panel.bmp" /boot/logo.bmp

# The V4 speaker sits behind an external amp fed from the codec's HP output: the
# shared rk3326 mixer default (DAC at -27 dB) is near-silent there. Full DAC gain.
if [ "$panel" = v4 ]; then
    amixer -q cset name='Playback Volume' 237 2>/dev/null
    alsactl store 2>/dev/null
fi
sync
