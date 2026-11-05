#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
# Charge-mode frames for charge-mode.sh: oakMOSS's charge screen (make-charge-screens.py card()) with
# dArkMoss's tree, name and background from logos/make-logo.py; the Miniloong's follow its minimal logo.
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

# fb0 as the kernel sets it up, the turn its logo has, and the frame style.
UNITS = {"g350": (640, 480, None, "card"), "xumini": (480, 640, "cw", "card"),
         "miniloong": (720, 960, "ccw", "minimal")}
TEXT = "Charging, press Power to turn on"
LEVELS = range(0, 101, 5)

# The Miniloong's minimal logo (misc/rk3566/device_off_charging_bmps/miniloong/logo.bmp): the tree alone,
# a quarter of the height tall, centred on #141414. TREE is spruce-tree.png's outline as 45-degree polygons
# (rasterized at 1x it is the 88x152 bitmap but for one stair pixel), so the tree stays sharp at any size.
TREE = [[(40, -0.5), (0.5, 39), (17.5, 56), (0.5, 73), (17, 89.5), (0, 106.5), (17.5, 124), (48.5, 93),
         (79.5, 124), (88.5, 115), (40.5, 67), (48.5, 59), (79.5, 90), (88, 81.5), (40, 33.5), (48, 25.5),
         (79, 56.5), (88, 47.5)],
        [(40, 118), (40, 152), (57, 152), (57, 118)]]
MIN_BG, UNLIT, SS = (20, 20, 20), (84, 84, 84), 8   # UNLIT: the off-charging BMPs' grey; SS: supersampling


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


def tree_mask(size, k, x0, y0, top=None):
    # TREE scaled by k at (x0, y0), drawn SS times larger and averaged down; top cuts off what is above it.
    big = Image.new("L", (size[0] * SS, size[1] * SS), 0)
    d = ImageDraw.Draw(big)
    for poly in TREE:
        d.polygon([((x * k + x0) * SS, (y * k + y0) * SS) for x, y in poly], fill=255)
    if top is not None:
        d.rectangle([0, 0, big.width, (top * k + y0) * SS], fill=0)
    return big.reduce(SS)


def check_tree():
    a = Image.open(ml.TREE).getchannel("A")
    off = sum((m > 127) != (v > 127) for m, v in zip(a.tobytes(), tree_mask(a.size, 1, 0, 0).tobytes()))
    if off > 1:
        sys.exit(f"make-frames.py: TREE no longer traces {ml.TREE} ({off} pixels differ)")


def minimal(w, h, level):
    # Landscape: the tree lit white from the trunk up to the level (the off-charging BMPs' idea, fb5a9fc),
    # the percentage under it, the hint at the bottom. level None: the logo itself.
    k = h / 4 / 152
    x0, y0 = (w - 88 * k) / 2, (h - 152 * k) / 2
    im = Image.new("RGB", (w, h), MIN_BG)
    lit = 100 if level is None else level
    im.paste(UNLIT, mask=tree_mask((w, h), k, x0, y0))
    if lit > 0:
        im.paste((255, 255, 255), mask=tree_mask((w, h), k, x0, y0, top=152 - 152.5 * lit / 100))
    if level is not None:
        s = h / 480
        d = ImageDraw.Draw(im)
        pf, hint = font(False, 22 * s), font(False, 15 * s)
        pct = f"{level}%"
        d.text(((w - d.textlength(pct, font=pf)) / 2, y0 + 152 * k + 22 * s), pct, font=pf, fill=(200, 200, 200))
        d.text(((w - d.textlength(TEXT, font=hint)) / 2, h - 40 * s), TEXT, font=hint, fill=(110, 110, 110))
    return im


def turn(im, rot):
    return {None: im, "cw": im.transpose(Image.Transpose.ROTATE_270),
            "ccw": im.transpose(Image.Transpose.ROTATE_90)}[rot]


def save(im, path):
    r, g, b = im.split()
    raw = Image.merge("RGBA", (b, g, r, Image.new("L", im.size, 255))).tobytes()
    with gzip.GzipFile(path, "wb", compresslevel=9, mtime=0) as f:
        f.write(raw)


def main(units):
    check_tree()
    for unit in units:
        w, h, rot, style = UNITS[unit]
        lw, lh = (h, w) if rot else (w, h)
        out = os.path.join(HERE, "frames", unit)
        os.makedirs(out, exist_ok=True)
        draw = minimal if style == "minimal" else card
        for level in LEVELS:
            save(turn(draw(lw, lh, level), rot), os.path.join(out, f"level-{level:03d}.raw.gz"))
        # The unit's own logo.bmp when it has one, so the frame is the picture U-Boot and bootlogo.py show.
        logo = os.path.join(HERE, "..", "..", "logos", unit, "logo.bmp")
        if style == "minimal":
            booting = turn(minimal(lw, lh, None), rot)
        else:
            booting = Image.open(logo).convert("RGB") if os.path.exists(logo) else turn(ml.logo(lw, lh), rot)
        save(booting, os.path.join(out, "booting.raw.gz"))
        with open(os.path.join(out, "fb"), "w") as f:
            f.write(f"{w} {h}\n")
        print(f"{unit}: {len(LEVELS)} level frames + booting ({w}x{h})")


if __name__ == "__main__":
    if not sys.argv[1:] or any(u not in UNITS for u in sys.argv[1:]):
        sys.exit(f"usage: make-frames.py <unit>...   units: {' '.join(UNITS)}")
    main(sys.argv[1:])
