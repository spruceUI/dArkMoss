#!/usr/bin/env python3
# The dArkMoss boot logo, laid out like oakMOSS's (scripts/make-boot-resource.py logo()): spruce's tree
# (spruce/imgs/tree_sm_close_crop.png) over the name on the SPRUCE theme's background, as a full-panel 24-bit BMP for U-Boot and bootlogo.py.
#   make-logo.py <width> <height> <out.bmp|out.png> [--rotate-cw|--rotate-ccw|--rotate-180] [--status TEXT] [--minimal]
#     --rotate-cw/--rotate-ccw: draw landscape, turn 90 degrees clockwise / counterclockwise (for a
#     portrait panel booted with fbcon=rotate:1 / rotate:3); --rotate-180: an upside-down panel (the V4);
#     --status: add oakMOSS's grey status line. A .png out is 8-bit grey, for the RK3566 kernel logo.
#     --minimal: the Miniloong's logo instead (make-miniloong-logos.py), the bare tree on #141414.
#     Panels shorter than 480 px get the layout scaled down to fit.
import importlib.util
import os
import sys

sys.dont_write_bytecode = True   # no __pycache__ in logos/ from importing make-miniloong-logos.py

from PIL import Image, ImageDraw, ImageFont

TREE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "spruce-tree.png")
FONTB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
if os.environ.get("DEJAVU_DIR"):  # as make-frames.py: DejaVu 2.37 where the system has none
    FONT = os.path.join(os.environ["DEJAVU_DIR"], "DejaVuSans.ttf")
    FONTB = os.path.join(os.environ["DEJAVU_DIR"], "DejaVuSans-Bold.ttf")
BG = (0x28, 0x28, 0x28, 255)  # spruce Themes/SPRUCE bgColor #282828


def logo(w, h, label="dArkMoss", status=None):
    k = min(1.0, min(w, h) / 480)  # 1 on the 640x480 / 720x720 panels the layout was made for
    im = Image.new("RGBA", (w, h), BG)
    tree = Image.open(TREE).convert("RGBA")
    tree = tree.resize((round(tree.width * 2 * k), round(tree.height * 2 * k)), Image.LANCZOS)
    font = ImageFont.truetype(FONTB, round(46 * k))
    d = ImageDraw.Draw(im)
    lw = d.textlength(label, font=font)
    asc, desc = font.getmetrics()
    gap = round(22 * k)
    top = (h - (tree.height + gap + asc + desc)) // 2
    im.alpha_composite(tree, ((w - tree.width) // 2, top))
    d.text(((w - lw) / 2, top + tree.height + gap), label, font=font, fill=(235, 235, 235, 255))
    if status:
        # oakMOSS's status line (make-charge-screens.py): DejaVu Sans 22, grey, in the strip below the name.
        small = ImageFont.truetype(FONT, round(22 * k))
        sasc, sdesc = small.getmetrics()
        below = top + tree.height + gap + asc + desc
        d.text(((w - d.textlength(status, font=small)) / 2, below + (h - below - sasc - sdesc) / 2),
               status, font=small, fill=(170, 170, 170, 255))
    return im.convert("RGB")


def minimal(w, h, status=None):
    # The Miniloong's logo: the bare tree a quarter of the height tall, centred; the status line
    # as logo()'s, in the strip under the tree.
    spec = importlib.util.spec_from_file_location("mml", os.path.join(os.path.dirname(TREE), "make-miniloong-logos.py"))
    mml = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mml)
    mml.check_tree()
    im = mml.logo(w, h).convert("RGB")
    if status:
        small = ImageFont.truetype(FONT, round(22 * min(1.0, min(w, h) / 480)))
        sasc, sdesc = small.getmetrics()
        d = ImageDraw.Draw(im)
        below = (h + h / 4) / 2
        d.text(((w - d.textlength(status, font=small)) / 2, below + (h - below - sasc - sdesc) / 2),
               status, font=small, fill=(170, 170, 170))
    return im


if __name__ == "__main__":
    argv, status = sys.argv[1:], None
    if "--status" in argv:
        i = argv.index("--status")
        status = argv[i + 1]
        del argv[i:i + 2]
    draw = minimal if "--minimal" in argv else logo
    args = [a for a in argv if a not in ("--rotate-cw", "--rotate-ccw", "--rotate-180", "--minimal")]
    if len(args) != 3:
        sys.exit("usage: make-logo.py <width> <height> <out.bmp|out.png> [--rotate-cw|--rotate-ccw|--rotate-180] "
                 "[--status TEXT] [--minimal]")
    w, h, out = int(args[0]), int(args[1]), args[2]
    if "--rotate-cw" in argv:
        im = draw(h, w, status=status).transpose(Image.Transpose.ROTATE_270)
    elif "--rotate-ccw" in argv:
        im = draw(h, w, status=status).transpose(Image.Transpose.ROTATE_90)
    else:
        im = draw(w, h, status=status)
        if "--rotate-180" in argv:
            im = im.transpose(Image.Transpose.ROTATE_180)
    # .png: an RK3566 kernel boot logo (ppmquant 224 takes it), 8-bit grey like make-miniloong-logos.py's.
    if out.endswith(".png"):
        im.convert("L").save(out, "PNG")
    else:
        im.save(out, "BMP")
