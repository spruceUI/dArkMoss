#!/usr/bin/python3 -I
# Redraw U-Boot's logo on the framebuffer the console blanked; on the first boot, its variant with
# "Setting up the card". tty1 output (firstboot's dialog, mount-spruce's messages) or the frontend's
# first frame replaces it.
#   bootlogo.py [--check]    --check converts and times it but leaves the screen alone
#   bootlogo.py --clear      once the frontend is DRM master, blacks out the logo it left in fb0,
#                            which would otherwise show the first time the frontend hands over the screen
import fcntl
import os
import struct
import sys
import time

LOGO, FIRSTBOOT, FB = "/boot/logo.bmp", "/boot/logo-firstboot.bmp", "/dev/fb0"
CLIENTS = "/sys/kernel/debug/dri/0/clients"
FBIOGET_VSCREENINFO = 0x4600


def main(check):
    t0 = time.monotonic()
    # firstboot.sh is gone once the card is set up.
    path = FIRSTBOOT if os.path.exists("/boot/firstboot.sh") and os.path.exists(FIRSTBOOT) else LOGO
    with open(path, "rb") as f:
        bmp = f.read()
    off, = struct.unpack_from("<I", bmp, 10)
    bw, bh = struct.unpack_from("<ii", bmp, 18)
    bits, comp = struct.unpack_from("<HI", bmp, 28)
    with open("/sys/class/graphics/fb0/stride") as f:
        stride = int(f.read())
    with open(FB, "r+b", buffering=0) as fb:
        v = fcntl.ioctl(fb, FBIOGET_VSCREENINFO, bytes(160))
        xres, yres, _, _, xoff, yoff, bpp = struct.unpack_from("7I", v)
        rgb = tuple(struct.unpack_from("I", v, 32 + 12 * i)[0] for i in range(3))
        # Only the plain case: an uncompressed 24-bit BMP the size of the screen, onto XRGB8888.
        if (bmp[:2] != b"BM" or bits != 24 or comp != 0 or (bw, abs(bh)) != (xres, yres)
                or bpp != 32 or rgb != (16, 8, 0) or xoff != 0 or stride < xres * 4):
            print(f"bootlogo: skipped, logo {bw}x{bh}x{bits} vs fb {xres}x{yres}x{bpp} {rgb}", file=sys.stderr)
            return
        row, opaque = (bw * 3 + 3) & ~3, b"\xff" * bw
        out = bytearray(stride * yres)
        for y in range(yres):
            s = off + (yres - 1 - y if bh > 0 else y) * row
            src, o = bmp[s:s + bw * 3], y * stride
            out[o:o + bw * 4:4] = src[0::3]
            out[o + 1:o + bw * 4:4] = src[1::3]
            out[o + 2:o + bw * 4:4] = src[2::3]
            out[o + 3:o + bw * 4:4] = opaque
        if not check:
            try:  # clear the console first, so no later console redraw brings its text back
                with open("/dev/tty1", "w") as tty:
                    tty.write("\033[H\033[2J")
            except OSError:
                pass
            fb.seek(yoff * stride)
            fb.write(out)
    print(f"bootlogo: {'checked' if check else 'drew'} {path} in {time.monotonic() - t0:.3f} s", file=sys.stderr)


def has_master():
    try:
        with open(CLIENTS) as f:
            return any(line.split()[3:4] == ["y"] for line in f.readlines()[1:])
    except OSError:
        return False


def clear(timeout=120):
    end = time.monotonic() + timeout
    while not has_master():
        if time.monotonic() > end:
            print("bootlogo: no DRM master, fb0 left as it is", file=sys.stderr)
            return
        time.sleep(0.5)
    with open("/sys/class/graphics/fb0/stride") as f:
        stride = int(f.read())
    with open(FB, "r+b", buffering=0) as fb:
        v = fcntl.ioctl(fb, FBIOGET_VSCREENINFO, bytes(160))
        _, yres, _, _, _, yoff = struct.unpack_from("6I", v)
        fb.seek(yoff * stride)
        fb.write(bytes(stride * yres))
    print("bootlogo: cleared fb0", file=sys.stderr)


if __name__ == "__main__":
    try:
        if "--clear" in sys.argv[1:]:
            clear()
        else:
            main("--check" in sys.argv[1:])
    except (OSError, ValueError, struct.error) as e:
        print(f"bootlogo: skipped, {e}", file=sys.stderr)
