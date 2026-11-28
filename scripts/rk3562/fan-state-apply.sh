#!/bin/sh
# Re-apply persistent fan-disabled state at boot.
# If the user previously ran "Disable Fan" from EmulationStation, unbind
# pwm-fan again so the kernel doesn't start ramping it up after boot.
[ -f /home/ark/.config/.FAN_DISABLED ] || exit 0
DRV=/sys/bus/platform/drivers/pwm-fan
[ -d "$DRV" ] || exit 0
for d in "$DRV"/*; do
    [ -L "$d" ] || continue
    n=$(basename "$d")
    case "$n" in bind|unbind|uevent|module) continue;; esac
    echo "$n" > "$DRV/unbind"
done
