#!/bin/bash

# The purpose of this script is to permanently set the resolution
# output for hdmi when connected.

xres="$(cat /sys/class/graphics/fb0/modes | grep -o -P '(?<=:).*(?=p-)' | cut -dx -f1)"

# drm_tool source available at https://github.com/christianhaitian/drm_tool.git

mode="$(sudo /usr/local/bin/drm_tool list | grep '1280x720 60' | head -1 | cut -d : -f 1)"

mode2="$(sudo /usr/local/bin/drm_tool list | grep '1920x1080 60' | head -1 | cut -d : -f 1)"

# Now we tell drm what the hdmi mode is by writing to /var/run/drmMode
# This will get picked up by SDL2 as long as it's been patched with the batocera
# drm resolution patch.  This patch can be found at 
# https://github.com/christianhaitian/rk3566_core_builds/raw/master/patches/sdl2-patch-0003-drm-resolution.patch

if [ $xres -eq "1280" ]; then
  echo $mode | sudo tee /var/run/drmMode
elif [ $xres -eq "1920" ]; then
  echo $mode2 | sudo tee /var/run/drmMode
else
  echo 0 | sudo tee /var/run/drmMode
  echo 1 | sudo tee /var/run/drmConn
fi

DEVICE="$(tr -d '\0' < /home/ark/.config/.DEVICE 2>/dev/null)"

# Only apply to the units with a rotated panel: the console's native rotation
# on the panel, 0 on HDMI.
case "$DEVICE" in
  *miniloong*|*MINILOONG*)
    PANEL_ROTATE=3
    ;;
  *e5plus*|*E5PLUS*)
    PANEL_ROTATE=1
    ;;
  *)
    exit 0
    ;;
esac

# Detect HDMI connection
for status in /sys/class/drm/card*-HDMI-A-*/status; do
  [ -e "$status" ] || continue
  if grep -q disconnected "$status"; then
    HDMI_STATUS="disconnected"
    break
  else
    HDMI_STATUS="connected"
    break
  fi
done

# fbcon rotation:
# 0 = normal
# 1 = 90 clockwise
# 2 = 180
# 3 = 270 clockwise
if [ "$HDMI_STATUS" = "connected" ]; then
  echo 0 > /sys/class/graphics/fbcon/rotate_all 2>/dev/null
else
  echo $PANEL_ROTATE > /sys/class/graphics/fbcon/rotate_all 2>/dev/null
fi