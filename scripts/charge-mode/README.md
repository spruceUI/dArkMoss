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
  tells a reboot from a plug-in. A charger must also stay online for 3 s before anything is drawn: a
  reset that bypasses Linux (reset key, watchdog) keeps `on=0x40` and leaves the register at 0, and on
  battery the unit would power off 3 s later instead of restarting. One read is not enough: after such a
  reset the V10 reads its DC detect online from probe until about 4 s. With no charger for 4 s, or none
  steady within 10 s, the unit boots. Every other boot returns at once. One line per boot goes to
  `/var/log/darkmoss-charge.log`; an entry names the supply that was online.
- `frames/<unit>/`: fb0's own bytes (XRGB8888) per 5 % level, plus `booting` (the unit's boot logo,
  drawn after Power) and `fb` (the size they were made for; another fb0 boots normally). A unit with
  two panels has a set per fb0 width (`a10mini/w640`, `a10mini/w720` for the V4). Regenerate with
  `make-frames.py <unit>` (Pillow, DejaVu 2.37; unit names as build_<unit>.sh exports them). The screen is
  the SPRUCE theme's charging icons (`logos/charging/`, MainUI's charging animation: the tree lit a part at
  a time), the one for the nearest quarter of the level, centred at the theme's size on the background of
  the unit's boot logo, with the percentage under it and the hint at the bottom. The RGB30 takes the
  960x720 set (the theme's 720x720 tree is drawn narrower); the V10 the 640x480 set scaled to 320 px.
- `install.sh`: sourced by `build_kernel.sh` / `build_kernel-rk3566.sh` before update-initramfs. It
  holds the opt-in list (every CI unit but the G350, the A10 Mini, the RG353M and the E5 Plus, which
  has its own charging screen, `scripts/e5plus/e5plus-offcharge.py`). Opted-in units also
  get `rockchip,uboot-charge-on = <0>`, so U-Boot's own animation does not run first: in BOOT's
  `uboot.dtb` (Mini M), and in the resource partition's `rk-kernel.dtb` on RK3566 (the
  RGB30's cached RG503 resource is unpacked and repacked for it). The V10's U-Boot (u-boot-rk3326)
  takes the animation's dtb and pictures from the board's SPI flash, which no image writes, so its
  BOOT gets a `manufacture` file instead: with it, odroidgoa.c skips `charge_display()`. U-Boot's
  low-battery hold is unchanged everywhere.
- `test/run.sh`: host test under busybox in bwrap on Linux. `run.sh install` alone (plain bash) runs
  install.sh with each CI unit's `export UNIT=` value: unit names here are those (the RG353M's is `353m`).
  Its `NOT_IN` list is for units left out on purpose, which must install nothing (the G350, the A10 Mini,
  the RG353M, the E5 Plus).

Wake keys are the power key and every key-only input node. Joypads that also report sticks are not
read: their axis events are more than the shell can follow.

Seen on hardware (2026-11-07): it works on the V10, RGB30, Miniloong and Mini M. The Miniloong
ran every step, the unplug power-off included (`charger removed at 92%; powering off`). The G350 and the
A10 Mini are left out: every boot they logged is `on=0x80` (the power key), and on 2026-11-19 neither
showed a charge screen at plug-in with charge mode installed. The RG353M is left out too: there is no unit to test
it on. Their frames stay.

On 2026-11-14 the Miniloong, Mini M and V10 ran the build before the 3 s rule (a charger online once
within 4 s): plug-in start, dark and wake, Power and the unplug power-off worked on all three. A reset key
after a charger start booted normally on the Mini M (`no charger online`) and on the Miniloong (its reset
gives `on=0x10`); the V10 drew the charge screen and powered off 4 s later, which the 3 s rule is for.
From 2026-11-14 (V10) to 11-19 the 3 s rule ran on the V10, Miniloong, Mini M and RGB30 (charger starts about
3 s later than before). After a reset the V10 and Mini M booted with `no charger online` or `ac online only
briefly`; the Miniloong's and the RGB30's reset gives `on=0x10`, which boots before the rule applies.
