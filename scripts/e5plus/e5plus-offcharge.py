#!/usr/bin/env python3
"""GameMT E5 Plus: charging screen when a charger switched the device on.

U-Boot's own charge mode never engages on this board, and without a serial
console there is no seeing why. So do it here, early in boot and before
spruce starts: the RK817 records why it powered up ("source: on=0x.." in the
kernel log). 0x40 is a charger plug-in, 0x80 the power key.

On a charger power-up, with the charger still in:
  - show the battery level (battery_0..5.bmp, already turned for this
    portrait panel) and blank the backlight after a few seconds;
  - a short press of power shows it again, holding power (1.5 s) carries on
    into spruce;
  - unplugging the charger powers the device off.
Anything else (power-key start, reboot, no log line) exits at once and the
boot goes on as usual.
"""
import fcntl
import glob
import mmap
import os
import re
import select
import struct
import subprocess
import sys
import time

IMG_DIR = "/usr/local/share/e5plus-offcharge"
PLUG_IN, PWRON_KEY = 0x40, 0x80
SCREEN_ON_S = 8
SCALE = 2  # the 110x220 icons are small on this panel
HOLD_TO_BOOT_S = 1.5
POLL_S = 0.5
EV_KEY, KEY_POWER = 1, 116
EVIOCGRAB = 0x40044590
KDSETMODE, KD_TEXT, KD_GRAPHICS = 0x4B3A, 0, 1


def log(msg):
    print("e5plus-offcharge: " + msg, flush=True)


def read(path, default=""):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return default


def power_on_source():
    try:
        out = subprocess.run(["dmesg"], capture_output=True, text=True).stdout
    except OSError:
        return None
    m = re.search(r"rk808 \S+: source: on=0x([0-9a-fA-F]+)", out)
    return int(m.group(1), 16) if m else None


def charger_online():
    for d in glob.glob("/sys/class/power_supply/*"):
        if read(d + "/type") in ("USB", "Mains") and read(d + "/online") == "1":
            return True
    return False


def capacity():
    for d in glob.glob("/sys/class/power_supply/*"):
        if read(d + "/type") == "Battery":
            try:
                return int(read(d + "/capacity", "0")), read(d + "/status")
            except ValueError:
                pass
    return 0, ""


def find_pwrkey():
    """The rk817 power key's event node (rk805-pwrkey driver)."""
    for _ in range(50):  # udev may still be creating nodes
        for ev in sorted(glob.glob("/sys/class/input/event*")):
            name = read(ev + "/device/name").lower()
            if "pwrkey" in name:
                return "/dev/input/" + os.path.basename(ev)
        time.sleep(0.1)
    return None


def load_bmp(path):
    """24-bit uncompressed BMP -> (w, h, rows of BGRX bytes, top first), SCALE x."""
    with open(path, "rb") as f:
        d = f.read()
    off, = struct.unpack_from("<I", d, 10)
    w, h = struct.unpack_from("<ii", d, 18)
    bpp, = struct.unpack_from("<H", d, 28)
    if bpp != 24:
        raise ValueError("%s: %d bpp" % (path, bpp))
    stride = (w * 3 + 3) & ~3
    rows = []
    for y in range(abs(h)):
        src = y if h < 0 else abs(h) - 1 - y
        line = d[off + src * stride: off + src * stride + w * 3]
        px = b"".join((line[i:i + 3] + b"\xff") * SCALE for i in range(0, len(line), 3))
        rows.extend([px] * SCALE)
    return w * SCALE, abs(h) * SCALE, rows


class Screen:
    def __init__(self):
        self.fb = None
        self.tty = None
        self.bl = None
        self.bl_level = None
        w, h = (int(v) for v in read("/sys/class/graphics/fb0/virtual_size", "0,0").split(","))
        bpp = int(read("/sys/class/graphics/fb0/bits_per_pixel", "0") or 0)
        stride = int(read("/sys/class/graphics/fb0/stride", "0") or 0) or w * bpp // 8
        if bpp != 32 or not w:
            log("framebuffer %sx%s %sbpp not supported, no picture" % (w, h, bpp))
            return
        self.w, self.h, self.stride = w, h, stride
        fd = os.open("/dev/fb0", os.O_RDWR)
        self.fb = mmap.mmap(fd, stride * h)
        os.close(fd)
        try:  # keep fbcon from drawing over the picture
            self.tty = os.open("/dev/tty1", os.O_RDWR)
            fcntl.ioctl(self.tty, KDSETMODE, KD_GRAPHICS)
        except OSError:
            self.tty = None
        bls = glob.glob("/sys/class/backlight/*")
        if bls:
            self.bl = bls[0]
            self.bl_level = read(self.bl + "/brightness")

    def show(self, bmp):
        if not self.fb:
            return
        self.fb[:] = b"\x00" * len(self.fb)
        w, h, rows = bmp
        x0, y0 = (self.w - w) // 2, (self.h - h) // 2
        for y, row in enumerate(rows):
            o = (y0 + y) * self.stride + x0 * 4
            self.fb[o:o + len(row)] = row

    def backlight(self, on):
        if self.bl:
            try:
                with open(self.bl + "/brightness", "w") as f:
                    f.write(self.bl_level if on else "0")
            except OSError:
                pass

    def close(self):
        self.backlight(True)
        if self.fb:
            self.fb[:] = b"\x00" * len(self.fb)
            self.fb.close()
        if self.tty is not None:
            try:
                fcntl.ioctl(self.tty, KDSETMODE, KD_TEXT)
            finally:
                os.close(self.tty)


def level_image(images):
    cap, status = capacity()
    idx = 5 if status == "Full" else min(5, max(0, cap * 6 // 100))
    return images[idx]


def main():
    src = power_on_source()
    if src is None or not (src & PLUG_IN) or (src & PWRON_KEY):
        return 0
    for _ in range(10):  # give the charger driver a moment to report
        if charger_online():
            break
        time.sleep(0.5)
    else:
        log("charger power-up but no charger now, powering off")
        subprocess.run(["systemctl", "poweroff"])
        return 0
    log("charger power-up (on=0x%02x): charging screen" % src)

    subprocess.run(["plymouth", "quit"], stderr=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
    images = []
    for n in range(6):
        try:
            images.append(load_bmp("%s/battery_%d.bmp" % (IMG_DIR, n)))
        except (OSError, ValueError) as e:
            log("no picture: %s" % e)
            images = None
            break

    key_path = find_pwrkey()
    key = os.open(key_path, os.O_RDONLY | os.O_NONBLOCK) if key_path else None
    if key is not None:
        try:
            fcntl.ioctl(key, EVIOCGRAB, 1)
        except OSError:
            pass
    else:
        log("no power key input found; holding power cannot continue the boot")

    screen = Screen()
    lit_until = time.monotonic() + SCREEN_ON_S
    pressed_at = None
    result = "boot"
    try:
        if images:
            screen.show(level_image(images))
        screen.backlight(True)
        last_draw = time.monotonic()
        while True:
            now = time.monotonic()
            if not charger_online():
                result = "off"
                break
            if pressed_at is not None and now - pressed_at >= HOLD_TO_BOOT_S:
                result = "boot"
                break
            if lit_until and now >= lit_until:
                screen.backlight(False)
                lit_until = 0
            if images and lit_until and now - last_draw >= 30:
                screen.show(level_image(images))
                last_draw = now
            fds = [key] if key is not None else []
            ready, _, _ = select.select(fds, [], [], POLL_S)
            if ready:
                data = os.read(key, 24 * 16)
                for i in range(0, len(data) - 23, 24):
                    _, _, etype, code, value = struct.unpack_from("<qqHHi", data, i)
                    if etype != EV_KEY or code != KEY_POWER:
                        continue
                    if value == 1:
                        pressed_at = time.monotonic()
                    elif value == 0 and pressed_at is not None:
                        pressed_at = None  # short press: show the level again
                        if images:
                            screen.show(level_image(images))
                            last_draw = time.monotonic()
                        screen.backlight(True)
                        lit_until = time.monotonic() + SCREEN_ON_S
    finally:
        if key is not None:
            try:
                fcntl.ioctl(key, EVIOCGRAB, 0)
            except OSError:
                pass
            os.close(key)
        screen.close()

    if result == "off":
        log("charger unplugged, powering off")
        subprocess.run(["systemctl", "poweroff"])
        time.sleep(30)  # keep spruce from starting while systemd shuts down
    else:
        log("power held, continuing the boot")
    return 0


if __name__ == "__main__":
    sys.exit(main())
