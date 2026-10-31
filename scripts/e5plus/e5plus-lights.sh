#!/bin/sh
# GameMT E5 Plus lights: the rings round both sticks and the two button
# backlights (led3, workled), all plain gpio-leds from the e5plus dts.
#
#   e5plus-lights.sh on | sticks-off | off   set a mode and remember it
#   e5plus-lights.sh cycle                   next mode; prints its name
#   e5plus-lights.sh restore                 apply the remembered mode (boot)
#   e5plus-lights.sh status                  print the remembered mode
STATE=/etc/e5plus-lights
LEDS=/sys/class/leds
STICKS="left_joystick right_joystick"
BUTTONS="led3 workled"

set_leds() {
    for _l in $1; do
        [ -w "$LEDS/$_l/brightness" ] && echo "$2" > "$LEDS/$_l/brightness"
    done
}

apply() {
    case "$1" in
        sticks-off) set_leds "$STICKS" 0; set_leds "$BUTTONS" 1 ;;
        off)        set_leds "$STICKS" 0; set_leds "$BUTTONS" 0 ;;
        *)          set_leds "$STICKS" 1; set_leds "$BUTTONS" 1 ;;
    esac
}

current() {
    _m="$(cat "$STATE" 2>/dev/null)"
    case "$_m" in on|sticks-off|off) echo "$_m" ;; *) echo on ;; esac
}

case "$1" in
    on|sticks-off|off) echo "$1" > "$STATE"; apply "$1" ;;
    cycle)
        case "$(current)" in
            on)         _next=sticks-off ;;
            sticks-off) _next=off ;;
            *)          _next=on ;;
        esac
        echo "$_next" > "$STATE"; apply "$_next"; echo "$_next" ;;
    restore) apply "$(current)" ;;
    status)  current ;;
    *) echo "usage: $0 on|sticks-off|off|cycle|restore|status" >&2; exit 1 ;;
esac
sync
