#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
# Charge-mode frames for charge-mode.sh: the SPRUCE theme's charging icons (logos/charging/, MainUI's
# charging animation: the tree lit a part at a time), centred on the unit's boot-logo background, the one for
# the nearest quarter of the level; the percentage under it and the hint at the bottom (#545454 and white,
# the icons' colours).
#   make-frames.py <unit>...   (Pillow + DejaVu 2.37; DEJAVU_DIR overrides /usr/share/fonts/truetype/dejavu)
# <unit> is build_<unit>.sh's `export UNIT=` value (353m for the RG353M), as install.sh matches it.
# Writes scripts/charge-mode/frames/<unit>/ (a unit with two panels: one folder per fb0 width, w<width>/):
# level-NNN.raw.gz (NNN = 0, 5 ... 100), booting.raw.gz (the unit's boot logo, drawn after the power key) and
# fb ("<width> <height>"). Frames are fb0's own bytes (XRGB8888: B, G, R, 0xff, as bootlogo.py writes) at its
# size, turned for the panel like the logo.
import gzip
import importlib.util
import os
import sys

sys.dont_write_bytecode = True   # no __pycache__ in logos/ from the imports below

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
LOGOS = os.path.join(HERE, "..", "..", "logos")


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, os.path.join(LOGOS, path))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


ml = _load("ml", "make-logo.py")
mm = _load("mm", "make-miniloong-logos.py")
if os.environ.get("DEJAVU_DIR"):
    ml.FONT = os.path.join(os.environ["DEJAVU_DIR"], "DejaVuSans.ttf")
    ml.FONTB = os.path.join(os.environ["DEJAVU_DIR"], "DejaVuSans-Bold.ttf")

# Per panel: fb0's size, the turn its logo has, the icon set (logos/charging/<skin>, scaled to the panel's
# height where the theme has none for it) and the logo as fb0 shows it (None: the Miniloong's, drawn by
# make-miniloong-logos.py), whose background the frames take.
UNITS = {
    "g350": [dict(fb=(640, 480), turn=None, icons="skin", logo="g350/logo.bmp")],
    "xumini": [dict(fb=(480, 640), turn="cw", icons="skin", logo="xumini/logo.bmp")],
    "v10": [dict(fb=(320, 480), turn="ccw", icons="skin", logo="v10/logo.bmp")],
    "miniloong": [dict(fb=(720, 960), turn="ccw", icons="skin_960x720", logo=None)],
    "rgb30": [dict(fb=(720, 720), turn=None, icons="skin_960x720", logo="unrotated/dArkMossrgb30.png")],
    "353m": [dict(fb=(640, 480), turn=None, icons="skin", logo="unrotated/dArkMoss353m.png")],   # the RG353M
    # One image for the A10 Mini and the V4 (720x540, upside down); a10mini-panel.sh's two logos.
    "a10mini": [dict(sub="w640", fb=(640, 480), turn=None, icons="skin", logo="unrotated/dArkMoss.bmp"),
                dict(sub="w720", fb=(720, 540), turn="180", icons="skin_720x540", logo="a10mini/logo-v4.bmp")],
}
TEXT = "Charging, press Power to turn on"
LEVELS = range(0, 101, 5)
WHITE, GREY = (255, 255, 255), (mm.UNLIT,) * 3


def font(bold, px):
    return ImageFont.truetype(ml.FONTB if bold else ml.FONT, max(8, round(px)))


def icon(skin, step, h):
    # charging-0<step>.png (1 unlit .. 5 all lit), scaled (premultiplied) to a panel of height h if its strip
    # is another height.
    im = Image.open(os.path.join(LOGOS, "charging", skin, f"charging-0{step}.png")).convert("RGBA")
    if im.height != h:
        k = h / im.height
        im = im.convert("RGBa").resize((round(im.width * k), h), Image.LANCZOS).convert("RGBA")
    return im


def frame(w, h, skin, bg, level):
    # Landscape: the icon for the nearest quarter (MainUI's 0/25/50/75/100 %) centred as MainUI draws its
    # strip, the percentage under the tree, the hint at the bottom.
    im = Image.new("RGBA", (w, h), (bg, bg, bg, 255))
    ic = icon(skin, int(level / 25 + 0.5) + 1, h)
    im.alpha_composite(ic, ((w - ic.width) // 2, 0))
    tree = icon(skin, 5, h).getchannel("A").point(lambda a: 255 if a > 127 else 0).getbbox()
    s = h / 480
    d = ImageDraw.Draw(im)
    pf, hint = font(False, 22 * s), font(False, 15 * s)
    pct = f"{level}%"
    d.text(((w - d.textlength(pct, font=pf)) / 2, tree[3] + 22 * s), pct, font=pf, fill=WHITE)
    d.text(((w - d.textlength(TEXT, font=hint)) / 2, h - 40 * s), TEXT, font=hint, fill=GREY)
    return im.convert("RGB")


def turn(im, rot):
    return {None: im, "cw": im.transpose(Image.Transpose.ROTATE_270),
            "ccw": im.transpose(Image.Transpose.ROTATE_90), "180": im.transpose(Image.Transpose.ROTATE_180)}[rot]


def save(im, path):
    r, g, b = im.split()
    raw = Image.merge("RGBA", (b, g, r, Image.new("L", im.size, 255))).tobytes()
    with gzip.GzipFile(path, "wb", compresslevel=9, mtime=0) as f:
        f.write(raw)


def logo_of(p):
    # The boot logo as fb0 shows it (turned like the frames).
    w, h = p["fb"]
    if p["logo"] is None:
        lw, lh = (h, w) if p["turn"] in ("cw", "ccw") else (w, h)
        return turn(mm.logo(lw, lh).convert("RGB"), p["turn"])
    im = Image.open(os.path.join(LOGOS, p["logo"])).convert("RGB")
    if im.size != (w, h):
        sys.exit(f"{p['logo']} is {im.size[0]}x{im.size[1]}, fb0 {w}x{h}")
    return im


def main(units):
    mm.check_tree()
    for unit in units:
        for p in UNITS[unit]:
            w, h = p["fb"]
            lw, lh = (h, w) if p["turn"] in ("cw", "ccw") else (w, h)
            booting = logo_of(p)
            # The logo's own background (its first pixel; every logo is a flat grey there).
            bg = booting.convert("L").getpixel((0, 0))
            out = os.path.join(HERE, "frames", unit, p.get("sub", ""))
            os.makedirs(out, exist_ok=True)
            for level in LEVELS:
                save(turn(frame(lw, lh, p["icons"], bg, level), p["turn"]), os.path.join(out, f"level-{level:03d}.raw.gz"))
            save(booting, os.path.join(out, "booting.raw.gz"))
            with open(os.path.join(out, "fb"), "w") as f:
                f.write(f"{w} {h}\n")
            print(f"{unit}{'/' + p['sub'] if 'sub' in p else ''}: {len(LEVELS)} level frames + booting ({w}x{h}, bg {bg})")


if __name__ == "__main__":
    if not sys.argv[1:] or any(u not in UNITS for u in sys.argv[1:]):
        sys.exit(f"usage: make-frames.py <unit>...   units: {' '.join(UNITS)}")
    main(sys.argv[1:])
