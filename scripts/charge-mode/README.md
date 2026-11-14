# Charge mode

Plugged in while off, the unit boots to a charge screen instead of spruce: the battery level and
"Charging, press Power to turn on", dark after 30 s, any key wakes it, Power boots, and 3 s without
the charger powers it off. It is oakMOSS's charge screen, ported from TwigUI-Next's Pixel 2 version
(spruceUI/twigUI-next `projects/twigUI/devices/RK3326S/packages/charge-mode`, same RK817 PMIC).

- `darkmoss-charge`: initramfs-tools `local-bottom` hook. Once the root is mounted it runs
  `charge-mode.sh` from it; exit 2 unmounts the root and powers off.
- `init-charge`: the same for the V10, which boots with no initramfs: boot.ini's `init=` runs it as
  PID 1 (root mounted rw, /dev from devtmpfs); it mounts /proc, /sys and /run, runs `charge-mode.sh`
  with busybox's applets first on the PATH, unmounts them and execs `/sbin/init`.
- `charge-mode.sh`: busybox only. It enters only on a cold plug-in power-on: rk808's
  `source: on=` line has bit 6 (plug-in) without bit 7 (power key), and the reboot-mode register
  (PMU_GRF + 0x200: 0xff010200 on RK3326, 0xfdc20200 on RK3566) reads 0. The RK817 keeps the last
  `on=` across a warm reboot (still 0x40 after a reboot on the Mini M), so the register is what
  tells a reboot from a plug-in. Every other boot returns at once. One line per boot goes to
  `/var/log/darkmoss-charge.log`.
- `frames/<unit>/`: fb0's own bytes (XRGB8888) per 5 % level, plus `booting` (the unit's boot logo,
  drawn after Power) and `fb` (the size they were made for; another fb0 boots normally). A unit with
  two panels can have a set per fb0 width (`w<width>/`, a `sub` in make-frames.py). Regenerate with
  `make-frames.py <unit>` (Pillow, DejaVu 2.37; unit names as build_<unit>.sh exports them). The screen is
  the SPRUCE theme's charging icons (`logos/charging/`, MainUI's charging animation: the tree lit a part at
  a time), the one for the nearest quarter of the level, centred at the theme's size on the background of
  the unit's boot logo, with the percentage under it and the hint at the bottom. The RGB30 takes the
  960x720 set (the theme's 720x720 tree is drawn narrower); the V10 the 640x480 set scaled to 320 px.
- `install.sh`: sourced by `build_kernel.sh` / `build_kernel-rk3566.sh` before update-initramfs. It
  holds the opt-in list: every CI unit but the A10 Mini, which never powers on at plug-in. Opted-in
  units also get `rockchip,uboot-charge-on = <0>`, so U-Boot's own animation does not run first: in
  BOOT's `uboot.dtb` (G350, Mini M) and in the resource partition's `rk-kernel.dtb` on RK3566 (the
  RGB30's cached RG503 resource is unpacked and repacked for it). The V10's U-Boot (u-boot-rk3326)
  takes the animation's dtb and pictures from the board's SPI flash, which no image writes, so its
  BOOT gets a `manufacture` file instead: with it, odroidgoa.c skips `charge_display()`. U-Boot's
  low-battery hold is unchanged everywhere.
- `test/run.sh`: host test under busybox in bwrap on Linux. `run.sh install` alone (plain bash) runs
  install.sh with each CI unit's `export UNIT=` value: unit names here are those (the RG353M's is `353m`).
  Its `NOT_IN` list holds the units left out on purpose (the A10 Mini), which must install nothing.

Wake keys are the power key and every key-only input node. Joypads that also report sticks are not
read: their axis events are more than the shell can follow.

Seen on hardware (2026-11-06): it works on the V10, RGB30, Miniloong and Mini M. The Miniloong
ran every step, the unplug power-off included (`charger removed at 92%; powering off`). The A10 Mini
does not power on at plug-in (every boot it logged is `on=0x80`, the power key), so it is left out;
the G350 may be the same. Not yet tested: the RG353M. Still open on the other units: the unplug
power-off and which key nodes wake them.
