#!/bin/sh
# Load the WiFi kernel driver that matches this device's hardware revision.
#
# Two RG52 Mini hardware revisions ship different WiFi chips on the same
# wireless-wlan DT node / power rail:
#   rev A: RK915 (Microchip WILC1000) -- SDIO vendor 0x0296
#   rev B: AIC8800DL (Aicsemi)        -- SDIO vendor 0xc8a1
# RG43H/V Pro are RK915-only.
#
# Both kernel drivers unconditionally pulse rockchip_wifi_power() at module
# init, so loading both at boot causes the second to stomp the first. Try
# rk915 first -- both drivers cleanly drop the rail when their chip isn't
# present, so if rk915 fails we can safely fall back to aic8800.
if ! modprobe rk915; then
    modprobe aic8800_bsp
    modprobe aic8800_fdrv
fi
