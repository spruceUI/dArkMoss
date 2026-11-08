#!/usr/bin/env python3
# The dArkMoss boot logo, laid out like oakMOSS's (scripts/make-boot-resource.py logo()): spruce's tree
# (spruce/imgs/tree_sm_close_crop.png) over the name on the SPRUCE theme's background, as a full-panel 24-bit BMP for U-Boot and bootlogo.py.
#   make-logo.py <width> <height> <out.bmp> [--rotate-cw|--rotate-ccw] [--status TEXT]
#     --rotate-cw/--rotate-ccw: draw landscape, turn 90 degrees clockwise / counterclockwise (for a
#     portrait panel booted with fbcon=rotate:1 / rotate:3); --status: add oakMOSS's grey status line.
#     Panels shorter than 480 px get the layout scaled down to fit.
import os
import sys

from PIL import Image, ImageDraw, ImageFont

TREE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "spruce-tree.png")
FONTB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
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


if __name__ == "__main__":
    argv, status = sys.argv[1:], None
    if "--status" in argv:
        i = argv.index("--status")
        status = argv[i + 1]
        del argv[i:i + 2]
    args = [a for a in argv if a not in ("--rotate-cw", "--rotate-ccw")]
    if len(args) != 3:
        sys.exit("usage: make-logo.py <width> <height> <out.bmp> [--rotate-cw|--rotate-ccw] [--status TEXT]")
    w, h, out = int(args[0]), int(args[1]), args[2]
    if "--rotate-cw" in argv:
        logo(h, w, status=status).transpose(Image.Transpose.ROTATE_270).save(out, "BMP")
    elif "--rotate-ccw" in argv:
        logo(h, w, status=status).transpose(Image.Transpose.ROTATE_90).save(out, "BMP")
    else:
        logo(w, h, status=status).save(out, "BMP")
