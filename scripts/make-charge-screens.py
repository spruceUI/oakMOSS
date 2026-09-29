#!/usr/bin/env python3
"""Charge-mode screens for the MagicX boards.

    scripts/make-charge-screens.py <board>

Plugged in while off, the SDK U-Boot (charge_mode = 1 in boards/<board>/sys_config.fex)
draws bat/battery_charge.bmp from the boot-resource partition and boots Linux with
androidboot.mode=charger; the base's charge-screen.sh then keeps a charging screen up with
the battery level until the power key, the way muOS's muxcharge does on the H700 boards.

Writes, for <board>:
  boards/<board>/boot-resource/bat/battery_charge.bmp   U-Boot's picture: the Linux level
      screen without its battery, cut to its content (24-bit), turned for the panel like
      the logo (make-boot-resource.py LOGO_ROT);
  boards/<board>/boot-resource/bootlogo.bmp   the board's own boot logo (make-boot-resource.py
      --logo), for the boards whose own boot chain would otherwise show the shared Zero 28
      logo (overlay/bootlogo.bmp, turned for its panel);
  boards/<board>/overlay/usr/magicx/share/charge/level-NNN.rgba.gz   the Linux screen at
      NNN = 0, 5, ... 100 %: the same, larger, plus a battery icon and the percentage;
  .../loading.rgba.gz   "Loading frontend", shown after the power key while the launcher starts.
The Linux frames are the framebuffer's own format (B, G, R, A bytes: ARGB8888, measured on the Zero 28
with one-byte colour bars)
at the size apps draw in; the kernel rotates them for the panel on every flip.
"""
import gzip, importlib.util, os, sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
_spec = importlib.util.spec_from_file_location("mbr", os.path.join(ROOT, "scripts", "make-boot-resource.py"))
mbr = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(mbr)

FB = {"zero28": (640, 480), "zero40": (480, 800), "xu20": (1024, 768)}   # the size apps draw in

CHARGE_TEXT = "Charging, press Power to turn on"
LEVELS = range(0, 101, 5)


def _font(bold, px):
    return ImageFont.truetype(mbr.FONTB if bold else mbr.FONT, max(8, round(px)))


def _tree(height):
    t = Image.open(mbr.TREE).convert("RGBA")
    return t.resize((round(t.width * height / t.height), round(height)), Image.LANCZOS)


def card(w, h, lines, battery=None, draw_battery=True):
    """The oakMOSS screen: tree, "oakMOSS", then smaller lines, then (optionally) the battery.
    draw_battery=False keeps the battery's room in the layout but leaves it black."""
    s = min(w / 640.0, h / 480.0)
    im = Image.new("RGBA", (w, h), (0, 0, 0, 255)); d = ImageDraw.Draw(im)
    tree = _tree(150 * s); title = _font(True, 46 * s); small = _font(False, 22 * s)
    asc, desc = title.getmetrics(); sasc, sdesc = small.getmetrics()
    parts = tree.height + 14 * s + asc + desc + len(lines) * (sasc + sdesc + 6 * s)
    if battery is not None:
        parts += 26 * s + 44 * s
    y = (h - parts) / 2
    im.alpha_composite(tree, (round((w - tree.width) / 2), round(y))); y += tree.height + 14 * s
    d.text(((w - d.textlength("oakMOSS", font=title)) / 2, y), "oakMOSS", font=title, fill=(235, 235, 235)); y += asc + desc
    for line in lines:
        y += 6 * s
        d.text(((w - d.textlength(line, font=small)) / 2, y), line, font=small, fill=(170, 170, 170)); y += sasc + sdesc
    if battery is not None and draw_battery:
        y += 26 * s
        bw, bh = 96 * s, 44 * s; pct = f"{battery}%"; pf = _font(True, 30 * s)
        total = bw + 8 * s + 18 * s + d.textlength(pct, font=pf)
        x = (w - total) / 2
        d.rectangle([x, y, x + bw, y + bh], outline=(235, 235, 235), width=max(2, round(3 * s)))
        d.rectangle([x + bw, y + bh * 0.3, x + bw + 8 * s, y + bh * 0.7], fill=(235, 235, 235))
        inner = 6 * s
        fill = (220, 60, 60) if battery < 15 else (80, 200, 90)
        if battery > 0:
            d.rectangle([x + inner, y + inner, x + inner + (bw - 2 * inner) * battery / 100, y + bh - inner], fill=fill)
        pasc, pdesc = pf.getmetrics()
        d.text((x + bw + 8 * s + 18 * s, y + (bh - pasc - pdesc) / 2), pct, font=pf, fill=(235, 235, 235))
    return im


def main(board):
    w, h = FB[board]
    share = os.path.join(ROOT, "boards", board, "overlay", "usr", "magicx", "share", "charge")
    os.makedirs(share, exist_ok=True)
    def save(name, im):
        with gzip.GzipFile(os.path.join(share, name + ".rgba.gz"), "wb", mtime=0) as f:
            r, g, b, a = im.convert("RGBA").split()
            f.write(Image.merge("RGBA", (b, g, r, a)).tobytes())
    for level in LEVELS:
        save(f"level-{level:03d}", card(w, h, [CHARGE_TEXT], battery=level))
    save("loading", card(w, h, ["Loading frontend"]))
    # U-Boot centres its picture, so the level screen with the battery left black, cut to
    # its content symmetrically about the centre: Linux's first frame then draws the same
    # tree and text at the same place and only the battery appears. It fits because each
    # board's sys_partition.fex gives its boot-resource partition room (1-2 MiB).
    full = card(w, h, [CHARGE_TEXT], battery=100, draw_battery=False).convert("RGB")
    x0, y0, x1, y1 = full.getbbox()
    m = 4; dx = max(w / 2 - x0, x1 - w / 2) + m; dy = max(h / 2 - y0, y1 - h / 2) + m
    bmp = full.crop((round(w / 2 - dx), round(h / 2 - dy), round(w / 2 + dx), round(h / 2 + dy)))
    rot = mbr.LOGO_ROT[board]
    bmp = bmp.rotate(rot, expand=True) if rot else bmp
    out = os.path.join(ROOT, "boards", board, "boot-resource", "bat")
    os.makedirs(out, exist_ok=True)
    bmp.save(os.path.join(out, "battery_charge.bmp"), format="BMP")
    if board != "zero28":
        mbr.logo(board).save(os.path.join(ROOT, "boards", board, "boot-resource", "bootlogo.bmp"), format="BMP")
    print(f"{board}: {len(LEVELS)} level frames + loading ({w}x{h}), battery_charge.bmp {bmp.size[0]}x{bmp.size[1]}")


if __name__ == "__main__":
    main(sys.argv[1])
