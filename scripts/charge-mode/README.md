# Charge mode

Plugged in while off, the unit boots to a charge screen instead of spruce: the battery level and
"Charging, press Power to turn on", dark after 30 s, any key wakes it, Power boots, and 3 s without
the charger powers it off. It is oakMOSS's charge screen, ported from Twig-Next's Pixel 2 version
(spruceUI/twigUI-next `projects/twigUI/devices/RK3326S/packages/charge-mode`, same RK817 PMIC).

- `darkmoss-charge`: initramfs-tools `local-bottom` hook. Once the root is mounted it runs
  `charge-mode.sh` from it; exit 2 unmounts the root and powers off.
- `charge-mode.sh`: busybox only. It enters only on a cold plug-in power-on: rk808's
  `source: on=` line has bit 6 (plug-in) without bit 7 (power key), and the reboot-mode register
  (PMU_GRF + 0x200: 0xff010200 on RK3326, 0xfdc20200 on RK3566) reads 0. Every other boot returns
  at once. One line per boot goes to `/var/log/darkmoss-charge.log`.
- `frames/<unit>/`: fb0's own bytes (XRGB8888) per 5 % level, plus `booting` (the boot logo, drawn
  after Power) and `fb` (the size they were made for; another fb0 boots normally). Regenerate with
  `make-frames.py <unit>` (Pillow, DejaVu 2.37). The Miniloong's follow its minimal logo: the tree
  alone, lit from the trunk up, drawn from a 45-degree polygon trace of `logos/spruce-tree.png`.
- `install.sh`: sourced by `build_kernel.sh` / `build_kernel-rk3566.sh` before update-initramfs. It
  holds the opt-in list. Opted-in units also get `rockchip,uboot-charge-on = <0>` (BOOT's `uboot.dtb`
  on RK3326, the resource partition's `rk-kernel.dtb` on RK3566), so U-Boot's own animation does
  not run first. U-Boot's low-battery hold is unchanged.
- `test/run.sh`: host test under busybox in bwrap on Linux.

Wake keys are the power key and every key-only input node. Joypads that also report sticks are not
read: their axis events are more than the shell can follow.

Not yet seen on hardware: whether each unit powers on at plug-in, its `on=` values, the panel
blank/unblank through fb0, and which key nodes exist in the initramfs.
