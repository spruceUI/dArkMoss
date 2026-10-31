#!/bin/sh
# GameMT E5 Plus: turn the light rings round both sticks on.
# The choice is kept in /etc/e5plus-lights and reapplied at every boot by
# dArkMoss's e5plus-lights.service.
if [ -x /usr/local/bin/e5plus-lights.sh ]; then
    /usr/local/bin/e5plus-lights.sh on
else
    for l in left_joystick right_joystick; do
        echo 1 > /sys/class/leds/$l/brightness 2>/dev/null
    done
    echo on > /etc/e5plus-lights 2>/dev/null
    sync
fi
