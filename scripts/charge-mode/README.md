# Charge mode

Plugged in while off, the unit boots to a charge screen instead of spruce: the battery level and
"Charging, press Power to turn on", dark after 30 s, any key wakes it, Power boots, and 3 s without
the charger powers it off. It is oakMOSS's charge screen, ported from Twig-Next's Pixel 2 version
(spruceUI/twigUI-next `projects/twigUI/devices/RK3326S/packages/charge-mode`, same RK817 PMIC).

- `darkmoss-charge`: initramfs-tools `local-bottom` hook. Once the root is mounted it runs
  `charge-mode.sh` from it; exit 2 unmounts the root and powers off.
- `init-charge`: the same for the V10, which boots with no initramfs: boot.ini's `init=` runs it as
  PID 1 (root mounted rw, /dev from devtmpfs); it mounts /proc, /sys and /run, runs `charge-mode.sh`
  with busybox's applets first on the PATH, unmounts them and execs `/sbin/init`.
- `charge-mode.sh`: busybox only. It enters only on a cold plug-in power-on: rk808's
  `source: on=` line has bit 6 (plug-in) without bit 7 (power key), and the reboot-mode register
  (PMU_GRF + 0x200: 0xff010200 on RK3326, 0xfdc20200 on RK3566) reads 0. Every other boot returns
  at once. One line per boot goes to `/var/log/darkmoss-charge.log`.
- `frames/<unit>/`: fb0's own bytes (XRGB8888) per 5 % level, plus `booting` (the unit's boot logo,
  drawn after Power) and `fb` (the size they were made for; another fb0 boots normally). A unit with
  two panels has a set per fb0 width (`a10mini/w640`, `a10mini/w720` for the V4). Regenerate with
  `make-frames.py <unit>` (Pillow, DejaVu 2.37). Every unit's follow the Miniloong's minimal style: the
  tree of its own boot logo, at the logo's place on the logo's background, lit white from the trunk up
  (#545454 unlit), the percentage under it (where the name is on the G350, Mini M and V10 logos) and the
  hint at the bottom. The tree is `logos/make-miniloong-logos.py`'s sharp one; that script also draws the
  Miniloong's U-Boot logo, charge steps and kernel logo, so there the Power frame is the logo pixel for
  pixel. The other logos are unchanged (resampled bitmaps: same place, softer edges).
- `install.sh`: sourced by `build_kernel.sh` / `build_kernel-rk3566.sh` before update-initramfs. It
  holds the opt-in list (every CI unit). Opted-in units also get `rockchip,uboot-charge-on = <0>`, so
  U-Boot's own animation does not run first: in BOOT's `uboot.dtb` (G350, Mini M) or
  `rg351mp-uboot.dtb` (A10 Mini), and in the resource partition's `rk-kernel.dtb` on RK3566 (the
  RGB30's cached RG503 resource is unpacked and repacked for it). The V10 ships no U-Boot dtb, so its
  U-Boot is unchanged. U-Boot's low-battery hold is unchanged everywhere.
- `test/run.sh`: host test under busybox in bwrap on Linux.

Wake keys are the power key and every key-only input node. Joypads that also report sticks are not
read: their axis events are more than the shell can follow.

Not yet seen on hardware: whether each unit powers on at plug-in, its `on=` values, the panel
blank/unblank through fb0, and which key nodes exist in the initramfs.
