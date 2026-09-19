#!/usr/bin/env python3
"""Board-sized bootloader screens for a stock boot-resource partition.

The stock MagicX boot-resource carries Android's verified-boot warnings
(orange/yellow/red, 800x1280) and a low-battery screen (480x800) sized for a
reference board. On the XU20 (framebuffer 1024x768) the stock U-Boot refuses
every one of them - "no support big size bmp[%dx%d] on fb[%dx%d]" is in its
binary - so each of those states shows whatever was on screen before: the boot
logo. A bootloader waiting for a power-key press, or shutting down on a flat
battery, is indistinguishable from a hang (2026-09-17, an afternoon of it).

This writes replacements that fit the board's framebuffer into a COPY of the
stock image (mtools from the SDK host tools; nothing is mounted), pre-rotated
for the panel the way the stock boot logo is, each carrying the state's name so
a photo of the screen names the U-Boot path. The boot logo gets a small tag so
a logo on screen proves this partition was the one read.

The boot logo is the spruce tree (assets/spruce-tree.png, from spruce's
spruce/imgs/tree_sm_close_crop.png) labelled "oakMOSS", on black, pre-rotated for
the panel. --logo writes it alone, for the Zero 28, whose own boot chain takes its
logo from overlay/bootlogo.bmp instead of a stock boot-resource.

    scripts/make-boot-resource.py <stock boot-resource.fex> <out.fex> <board>
    scripts/make-boot-resource.py --logo <board> <out.bmp>

The bitmaps are 24-bit BMP; U-Boot's parser takes 24/32 bpp, bottom-up rows.
"""
import os, subprocess, sys
from PIL import Image, ImageDraw, ImageFont

BOARDS = {"xu20": (1024, 768, 180), "zero40": (480, 800, 0), "zero28": (480, 640, 90)}
# How the boot logo is turned for each panel (PIL rotate, counter-clockwise): the XU20's
# panel scans upside down, the Zero 40's is upright, and the Zero 28's is mounted portrait
# with the picture turned 90 degrees clockwise - the way its long-standing overlay logo
# (the SDK original rotated 270) has always been drawn.
LOGO_ROT = {"xu20": 180, "zero40": 0, "zero28": 270}
# Logo side in pixels. The Zero 28's own boot chain gives its boot-resource partition
# only 512 sectors (256 KiB); a 400 px 32-bit logo (640 KB) made the SDK pack fail with
# "dl file boot-resource.fex size too large" (2026-09-18), so it gets 200 px (160 KB).
LOGO_SIZE = {"xu20": 400, "zero40": 400, "zero28": 200}
TREE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "spruce-tree.png")
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONTB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
MCOPY = os.environ.get("MCOPY", os.path.join(os.environ.get("SDK_DIR", ""), "out/host/bin/mcopy"))
# Allwinner's fsbuild leaves the BPB heads/sectors fields at zero; nothing that reads
# a FAT by cluster chain looks at them, but mtools refuses the image unless told not to.
os.environ.setdefault("MTOOLS_SKIP_CHECK", "1")

SCREENS = [  # name, colour, title, body lines, action line
    ("yellow_pause_warning", (255, 204, 0), "Your device has loaded a different operating system.",
     ["The bootloader (verified boot, YELLOW state) is pausing.", "Boot continues by itself in 5 seconds."],
     "PRESS POWER once now = PAUSE here until pressed again."),
    ("yellow_continue_warning", (255, 204, 0), "Boot is paused.",
     ["The bootloader is waiting for you.", "Nothing else is wrong yet."],
     "PRESS POWER once to CONTINUE booting."),
    ("orange_warning", (255, 140, 0), "Your device software can't be checked for corruption.",
     ["Bootloader is unlocked (ORANGE state).", "Boot continues by itself in 5 seconds."],
     "DO NOT press power here: a press SHUTS DOWN."),
    ("red_warning", (255, 60, 60), "Your device is corrupt.",
     ["Verified boot (RED state) refused the boot image.", "It cannot boot; hold power to turn off."],
     "Reflash SD1."),
]


def wrap(d, text, font, width):
    """Greedy word wrap measured with the real font, so nothing runs off the panel."""
    out, line = [], ""
    for word in text.split():
        cand = (line + " " + word).strip()
        if d.textlength(cand, font=font) <= width or not line:
            line = cand
        else:
            out.append(line); line = word
    if line:
        out.append(line)
    return out


def screen(w, h, rot, name, col, title, lines, action):
    s = w / 1024.0
    f, fb, fs = (ImageFont.truetype(p, int(n * s)) for p, n in ((FONT, 30), (FONTB, 34), (FONT, 20)))
    im = Image.new("RGB", (w, h), "black"); d = ImageDraw.Draw(im)
    x0, y = int(180 * s), int(100 * s); width = w - x0 - int(40 * s)
    tri = int(80 * s); tx, ty = int(70 * s), y
    d.polygon([(tx, ty + tri), (tx + tri // 2, ty), (tx + tri, ty + tri)], fill=col)
    d.rectangle([tx + tri // 2 - 5, ty + tri * 0.35, tx + tri // 2 + 5, ty + tri * 0.72], fill="black")
    for l in wrap(d, title, fb, width):
        d.text((x0, y), l, font=fb, fill=col); y += int(44 * s)
    y += int(24 * s)
    for para in lines:
        for l in wrap(d, para, f, width):
            d.text((x0, y), l, font=f, fill="white"); y += int(40 * s)
    y += int(30 * s)
    for l in wrap(d, action, fb, width):
        d.text((x0, y), l, font=fb, fill=col); y += int(44 * s)
    d.text((x0, h - int(70 * s)), f"oakMOSS boot-resource - bootloader state: {name}", font=fs, fill=(120, 120, 120))
    return im.rotate(rot, expand=True) if rot in (90, 270) else im.rotate(rot)


def low_pwr(w, h, rot):
    im = Image.new("RGB", (w, h), "black"); d = ImageDraw.Draw(im); s = w / 1024.0
    cx, cy = w // 2, h // 2 - int(60 * s)
    d.rectangle([cx - 100 * s, cy - 60 * s, cx + 100 * s, cy + 60 * s], outline="white", width=max(2, int(6 * s)))
    d.rectangle([cx + 100 * s, cy - 20 * s, cx + 120 * s, cy + 20 * s], fill="white")
    d.rectangle([cx - 88 * s, cy - 48 * s, cx - 42 * s, cy + 48 * s], fill=(255, 60, 60))
    f = ImageFont.truetype(FONT, int(34 * s)); fs = ImageFont.truetype(FONT, int(24 * s))
    d.text((int(300 * s), cy + int(110 * s)), "Battery too low to start. Charging, then powering off.", font=f, fill="white")
    d.text((int(200 * s), h - int(70 * s)), "oakMOSS boot-resource - bootloader state: low_pwr", font=fs, fill=(120, 120, 120))
    return im.rotate(rot, expand=True) if rot in (90, 270) else im.rotate(rot)


def logo(board):
    """The spruce tree with "oakMOSS" beneath it, on black, turned for the panel: a square
    of LOGO_SIZE (the tree at twice its size at 400 px), which U-Boot centres in the
    framebuffer."""
    size = LOGO_SIZE[board]; k = size / 400.0
    im = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    tree = Image.open(TREE).convert("RGBA")
    tree = tree.resize((round(tree.width * 2 * k), round(tree.height * 2 * k)), Image.LANCZOS)
    font = ImageFont.truetype(FONTB, round(46 * k))
    d = ImageDraw.Draw(im)
    label = "oakMOSS"
    lw = d.textlength(label, font=font); asc, desc = font.getmetrics()
    gap = round(22 * k)
    top = (size - (tree.height + gap + asc + desc)) // 2
    im.alpha_composite(tree, ((size - tree.width) // 2, top))
    d.text(((size - lw) / 2, top + tree.height + gap), label, font=font, fill=(235, 235, 235, 255))
    rot = LOGO_ROT[board]
    return im.rotate(rot, expand=True) if rot else im


def main(stock, out, board):
    w, h, rot = BOARDS[board]
    if not os.access(MCOPY, os.X_OK):
        raise SystemExit(f"need the SDK's mcopy (set SDK_DIR or MCOPY); {MCOPY!r} is not executable")
    work = out + ".work"; os.makedirs(work, exist_ok=True)
    import shutil; shutil.copyfile(stock, out)
    files = []
    for name, col, title, lines, action in SCREENS:
        p = os.path.join(work, name + ".bmp"); screen(w, h, rot, name, col, title, lines, action).save(p, format="BMP"); files.append((p, f"::{name}.bmp"))
    p = os.path.join(work, "low_pwr.bmp"); low_pwr(w, h, rot).save(p, format="BMP"); files.append((p, "::bat/low_pwr.bmp"))
    # The boot logo: the spruce tree labelled oakMOSS. 32-bit like the stock logo it
    # replaces (the fastlogo path is the one place a different bpp might matter), while
    # the warnings stay 24-bit like the vendor's.
    p = os.path.join(work, "bootlogo.bmp"); logo(board).save(p, format="BMP"); files.append((p, "::bootlogo.bmp"))
    for src, dst in files:
        subprocess.run([MCOPY, "-o", "-i", out, src, dst], check=True)
    print(f"{out}: {len(files)} screens for {board} ({w}x{h}, panel rotation {rot})")


if __name__ == "__main__":
    if sys.argv[1:2] == ["--logo"]:
        logo(sys.argv[2]).save(sys.argv[3], format="BMP")
        print(f"{sys.argv[3]}: oakMOSS boot logo for {sys.argv[2]}")
    else:
        main(*sys.argv[1:4])
