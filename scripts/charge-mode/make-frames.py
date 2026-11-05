#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
# Charge-mode frames for charge-mode.sh: oakMOSS's charge screen (make-charge-screens.py card()) with
# dArkMoss's tree, name and background from logos/make-logo.py.
#   make-frames.py <unit>...   (Pillow + DejaVu 2.37; DEJAVU_DIR overrides /usr/share/fonts/truetype/dejavu)
# Writes scripts/charge-mode/frames/<unit>/: level-NNN.raw.gz (NNN = 0, 5 ... 100), booting.raw.gz (the
# boot logo, drawn after the power key) and fb ("<width> <height>"). Frames are fb0's own bytes
# (XRGB8888: B, G, R, 0xff, as bootlogo.py writes) at its size, turned for the panel like the logo.
import gzip
import importlib.util
import os
import sys

sys.dont_write_bytecode = True   # no __pycache__ in logos/ from the import below

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("ml", os.path.join(HERE, "..", "..", "logos", "make-logo.py"))
ml = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ml)
if os.environ.get("DEJAVU_DIR"):
    ml.FONT = os.path.join(os.environ["DEJAVU_DIR"], "DejaVuSans.ttf")
    ml.FONTB = os.path.join(os.environ["DEJAVU_DIR"], "DejaVuSans-Bold.ttf")

# fb0 as the kernel sets it up, and the turn make-logo.py gives that unit's logo.bmp.
UNITS = {"g350": (640, 480, None), "xumini": (480, 640, "cw"), "miniloong": (720, 960, "ccw")}
TEXT = "Charging, press Power to turn on"
LEVELS = range(0, 101, 5)


def font(bold, px):
    return ImageFont.truetype(ml.FONTB if bold else ml.FONT, max(8, round(px)))


def card(w, h, level):
    # oakMOSS's layout, landscape: tree, name, the grey line, then the battery and its percentage.
    s = min(w / 640.0, h / 480.0)
    im = Image.new("RGBA", (w, h), ml.BG)
    d = ImageDraw.Draw(im)
    tree = Image.open(ml.TREE).convert("RGBA")
    tree = tree.resize((round(tree.width * 150 * s / tree.height), round(150 * s)), Image.LANCZOS)
    title, small, pf = font(True, 46 * s), font(False, 22 * s), font(True, 30 * s)
    asc, desc = title.getmetrics()
    sasc, sdesc = small.getmetrics()
    bw, bh, nub = 96 * s, 44 * s, 8 * s
    y = (h - (tree.height + 14 * s + asc + desc + 6 * s + sasc + sdesc + 26 * s + bh)) / 2
    im.alpha_composite(tree, (round((w - tree.width) / 2), round(y)))
    y += tree.height + 14 * s
    d.text(((w - d.textlength("dArkMoss", font=title)) / 2, y), "dArkMoss", font=title, fill=(235, 235, 235))
    y += asc + desc + 6 * s
    d.text(((w - d.textlength(TEXT, font=small)) / 2, y), TEXT, font=small, fill=(170, 170, 170))
    y += sasc + sdesc + 26 * s
    pct = f"{level}%"
    x = (w - (bw + nub + 18 * s + d.textlength(pct, font=pf))) / 2
    d.rectangle([x, y, x + bw, y + bh], outline=(235, 235, 235), width=max(2, round(3 * s)))
    d.rectangle([x + bw, y + bh * 0.3, x + bw + nub, y + bh * 0.7], fill=(235, 235, 235))
    if level > 0:
        inner = 6 * s
        fill = (220, 60, 60) if level < 15 else (80, 200, 90)
        d.rectangle([x + inner, y + inner, x + inner + (bw - 2 * inner) * level / 100, y + bh - inner], fill=fill)
    pasc, pdesc = pf.getmetrics()
    d.text((x + bw + nub + 18 * s, y + (bh - pasc - pdesc) / 2), pct, font=pf, fill=(235, 235, 235))
    return im.convert("RGB")


def turn(im, rot):
    return {None: im, "cw": im.transpose(Image.Transpose.ROTATE_270),
            "ccw": im.transpose(Image.Transpose.ROTATE_90)}[rot]


def save(im, path):
    r, g, b = im.split()
    raw = Image.merge("RGBA", (b, g, r, Image.new("L", im.size, 255))).tobytes()
    with gzip.GzipFile(path, "wb", compresslevel=9, mtime=0) as f:
        f.write(raw)


def main(units):
    for unit in units:
        w, h, rot = UNITS[unit]
        lw, lh = (h, w) if rot else (w, h)
        out = os.path.join(HERE, "frames", unit)
        os.makedirs(out, exist_ok=True)
        for level in LEVELS:
            save(turn(card(lw, lh, level), rot), os.path.join(out, f"level-{level:03d}.raw.gz"))
        # The unit's own logo.bmp when it has one, so the frame is the picture U-Boot and bootlogo.py show.
        logo = os.path.join(HERE, "..", "..", "logos", unit, "logo.bmp")
        save(Image.open(logo).convert("RGB") if os.path.exists(logo) else turn(ml.logo(lw, lh), rot),
             os.path.join(out, "booting.raw.gz"))
        with open(os.path.join(out, "fb"), "w") as f:
            f.write(f"{w} {h}\n")
        print(f"{unit}: {len(LEVELS)} level frames + booting ({w}x{h})")


if __name__ == "__main__":
    if not sys.argv[1:] or any(u not in UNITS for u in sys.argv[1:]):
        sys.exit(f"usage: make-frames.py <unit>...   units: {' '.join(UNITS)}")
    main(sys.argv[1:])
