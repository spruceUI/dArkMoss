#!/usr/bin/env python3
# The Miniloong's minimal tree pictures, drawn from TREE (spruce-tree.png traced as 45-degree polygons) so
# the edges stay sharp at any size; fb5a9fc's were the 88x152 bitmap resampled.
#   make-miniloong-logos.py   (Pillow)
# Writes, turned 90 degrees counterclockwise for the panel as fb5a9fc's were (fbcon turns the kernel's):
#   misc/rk3566/device_off_charging_bmps/miniloong/logo.bmp, logo_kernel.bmp: U-Boot's logo, the tree a quarter
#     of the height tall on #141414, 8-bit grey so both copies fit the 4 MB resource partition;
#   .../battery_0..5.bmp: U-Boot's off-charging steps, the tree lit from the trunk up a tier at a time;
#   logos/unrotated/dArkMossminiloong.png: the kernel's boot logo (ppmquant 224 takes it), 8-bit grey.
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "spruce-tree.png")
RES = os.path.join(HERE, "..", "misc", "rk3566", "device_off_charging_bmps", "miniloong")

# Crown and trunk in spruce-tree.png's pixels; every crown edge is at 45 degrees. Rasterized at 1x it is
# the bitmap but for one stair pixel (check_tree).
TREE = [[(40, -0.5), (0.5, 39), (17.5, 56), (0.5, 73), (17, 89.5), (0, 106.5), (17.5, 124), (48.5, 93),
         (79.5, 124), (88.5, 115), (40.5, 67), (48.5, 59), (79.5, 90), (88, 81.5), (40, 33.5), (48, 25.5),
         (79, 56.5), (88, 47.5)],
        [(40, 118), (40, 152), (57, 152), (57, 118)]]
BG, UNLIT, SS = 20, 84, 8   # logo background, the off-charging steps' unlit grey, supersampling


def tree_mask(size, k, x0, y0, polys=TREE, clear=None, ss=SS):
    # polys scaled by k at (x0, y0), minus the clear polygon, drawn ss times larger (ss 1: not averaged).
    big = Image.new("L", (size[0] * ss, size[1] * ss), 0)
    d = ImageDraw.Draw(big)
    pt = lambda p: [((x * k + x0) * ss, (y * k + y0) * ss) for x, y in p]
    for poly in polys:
        d.polygon(pt(poly), fill=255)
    if clear:
        d.polygon(pt(clear), fill=0)
    return big.reduce(ss) if ss > 1 else big


def tree_image(size, k, x0, y0, bg, unlit=None, lit=None):
    # Grey: the tree in unlit grey, then lit (tree_mask's polys/clear, {} for all of it) in white, drawn SS
    # times larger and averaged down once, so every edge blends with what is really next to it.
    big = Image.new("L", (size[0] * SS, size[1] * SS), bg)
    if unlit is not None:
        big.paste(unlit, mask=tree_mask(big.size, k * SS, x0 * SS, y0 * SS, ss=1))
    if lit is not None:
        big.paste(255, mask=tree_mask(big.size, k * SS, x0 * SS, y0 * SS, ss=1, **lit))
    return big.reduce(SS)


def above(top):
    return [(-10, -10), (100, -10), (100, top), (-10, top)]


def above_tier(apex):
    # Everything over a "^" through (40, apex), parallel to the tier edges: apex 66.5 leaves the bottom
    # tier and the trunk, 33.5 the middle tier too.
    return [(-10, -10), (100, -10), (100, apex + 60), (40, apex), (-10, apex + 50)]


def check_tree():
    a = Image.open(SRC).getchannel("A")
    off = sum((m > 127) != (v > 127) for m, v in zip(a.tobytes(), tree_mask(a.size, 1, 0, 0).tobytes()))
    if off > 1:
        sys.exit(f"TREE no longer traces {SRC} ({off} pixels differ)")


def logo(w, h):
    # Landscape grey: the tree a quarter of the height tall, centred.
    k = h / 4 / 152
    return tree_image((w, h), k, (w - 88 * k) / 2, (h - 152 * k) / 2, BG, lit={})


def grey_bmp(im, path):
    # 8-bit with only the greys it uses, lightest first, as fb5a9fc's.
    levels = sorted(set(im.tobytes()), reverse=True)
    index = {v: i for i, v in enumerate(levels)}
    p = im.point(lambda v: index.get(v, 0)).convert("P")
    p.putpalette([c for v in levels for c in (v, v, v)])
    p.save(path, "BMP")


def battery(step):
    # Upright 98x153, the tree 126 px tall on black: 0 unlit, 1 the trunk, 2 + the bottom tier,
    # 3 + the middle tier, 4 and 5 all lit (the charge animation's 6 images, fb5a9fc's steps).
    w, h = 98, 153
    k = 126 / 152
    x0, y0 = (w - 88 * k) / 2, (h - 152 * k) / 2
    lit = {0: None, 1: dict(polys=TREE[1:]), 2: dict(clear=above_tier(66.5)), 3: dict(clear=above_tier(33.5)),
           4: {}, 5: {}}[step]
    return tree_image((w, h), k, x0, y0, 0, unlit=UNLIT, lit=lit)


def main():
    check_tree()
    ccw = Image.Transpose.ROTATE_90
    lg = logo(960, 720)
    for name in ("logo.bmp", "logo_kernel.bmp"):
        grey_bmp(lg.transpose(ccw), os.path.join(RES, name))
    lg.save(os.path.join(HERE, "unrotated", "dArkMossminiloong.png"), "PNG")
    for step in range(6):
        battery(step).transpose(ccw).convert("RGB").save(os.path.join(RES, f"battery_{step}.bmp"), "BMP")
    print(f"miniloong: logo.bmp, logo_kernel.bmp ({len(set(lg.tobytes()))} greys), dArkMossminiloong.png, battery_0..5.bmp")


if __name__ == "__main__":
    main()
