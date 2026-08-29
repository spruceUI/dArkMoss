#!/bin/sh
# Detach the text console from the panel before the frontend starts.
#
# spruce's transition splash is drawn by PyUI itself - display_image_and_text()
# sends an IMAGE_AND_TEXT message over PyUI's socket rather than touching the
# framebuffer - so while PyUI is exiting to hand a game the display, nothing is
# painting the panel. fbcon fills that gap with tty1, and spruce-launch used to
# have its stdout there, so every launch and exit flashed the console with
# spruce narrating its own scripts. Unbinding fbcon leaves the panel to whoever
# holds DRM.
#
# /dev/fb0 is untouched and still displays, so anything writing to it directly
# keeps working. This is a runtime binding, not a kernel parameter - nothing
# here changes how the machine boots.
#
# Left bound when /boot/darkmoss-debug exists. That flag already means "I am
# debugging this device" (see darkmoss-debug.sh), and a debugger wants console
# output and panics on the screen. It is also the escape hatch if unbinding ever
# turns out to break a display path: drop the file on the FAT partition from any
# PC and the console comes back.
#
# Match on the device name rather than hardcoding vtcon1: vtcon0 is the dummy
# console and vtcon1 the framebuffer one on the RGB30, but that numbering is not
# guaranteed.

[ -e /boot/darkmoss-debug ] && exit 0

for vtcon in /sys/class/vtconsole/vtcon*; do
    [ -e "$vtcon/name" ] || continue
    case "$(cat "$vtcon/name" 2>/dev/null)" in
        *"frame buffer device"*)
            echo 0 > "$vtcon/bind" 2>/dev/null
            ;;
    esac
done

exit 0
