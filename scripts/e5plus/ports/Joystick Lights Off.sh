#!/bin/sh
# GameMT E5 Plus: turn the light rings round both sticks off.
# The choice is kept in /etc/e5plus-lights and reapplied at every boot by
# dArkMoss's e5plus-lights.service.
if [ -x /usr/local/bin/e5plus-lights.sh ]; then
    /usr/local/bin/e5plus-lights.sh sticks-off
else
    for l in left_joystick right_joystick; do
        echo 0 > /sys/class/leds/$l/brightness 2>/dev/null
    done
    echo sticks-off > /etc/e5plus-lights 2>/dev/null
    sync
fi
