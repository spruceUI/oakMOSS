#!/usr/bin/env python3
"""The Brick's card on our own U-Boot (feat/brick-own-uboot): the two pieces that differ from TrimUI's chain.

    scripts/make-brick-own-uboot.py <TrimUI package> <TrimUI boot-resource> <SDK image> <out dir>

  <TrimUI package>        TrimUI's boot package (unpack-trimui-stock.sh: items/12345678_BOOTPKG-00000000)
  <TrimUI boot-resource>  TrimUI's boot-resource FAT (items/RFSFAT16_BOOT-RESOURCE_FE)
  <SDK image>             any oakMOSS SDK-lane sd1.img of the same build: our U-Boot is one binary for every
                          board (B205: byte-identical on the Zero 28, Zero 40 and XU20), read from its package

Writes into <out dir>:
  package.bin   TrimUI's package with only its u-boot item replaced by ours; boot0 (TrimUI's DRAM setup),
                BL31, SCP and the device tree stay TrimUI's. The toc1 checksum is fixed and checked.
  bootres.fat   TrimUI's boot-resource with our U-Boot pictures (boards/brick/boot-resource: bootlogo.bmp and
                bat/{battery_charge,bat0,low_pwr}.bmp, make-charge-screens.py brick) in place of TrimUI's; every
                other file (bat1-5, magic.bin) and the FAT's size stay.
  MANIFEST.txt  what was taken from where, with sha256s.
A card takes package.bin at sector 32800 only (the main copy): boot0 falls back to the spare copy at 24576,
which stays TrimUI's, when the main one fails its checksum. bootres.fat goes to the start of p1.
"""
import hashlib, importlib.util, os, struct, subprocess, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
S = 512


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, os.path.join(ROOT, "scripts", file))
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m


def sha(b):
    return hashlib.sha256(b).hexdigest()


def tool(*args):
    r = subprocess.run([sys.executable, "-I", os.path.join(ROOT, "scripts", args[0])] + list(args[1:]),
                       capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"{args[0]} {' '.join(args[1:])}: {r.stdout}{r.stderr}")
    return r.stdout


def main():
    if len(sys.argv) != 5:
        sys.exit(__doc__.strip().splitlines()[2].strip())
    pkg_in, bootres_in, sdk_img, out = sys.argv[1:]
    os.makedirs(out, exist_ok=True)
    pics = os.path.join(ROOT, "boards", "brick", "boot-resource")
    man = []

    # 1. our U-Boot, out of the SDK image's own package
    with open(sdk_img, "rb") as f:
        f.seek(32800 * S); sdk_pkg = f.read(4 << 20)
    tmp = os.path.join(out, ".sdk-package.bin"); open(tmp, "wb").write(sdk_pkg)
    ours = os.path.join(out, ".u-boot.bin"); tool("toc1-item.py", "--extract", tmp, "u-boot", ours)
    u = open(ours, "rb").read()
    if b"U-Boot 2018.05" not in u:
        sys.exit("the SDK image's u-boot item is not U-Boot 2018.05")
    man.append(f"u-boot  {sha(u)}  {len(u)} B, from {os.path.basename(sdk_img)}'s package")

    # 2. TrimUI's package with that u-boot; everything else is TrimUI's
    stock = open(pkg_in, "rb").read()
    pkg = os.path.join(out, "package.bin"); open(pkg, "wb").write(stock)
    tool("toc1-item.py", "--replace", pkg, "u-boot", ours)
    tool("toc1-checksum.py", "--fix", pkg); tool("toc1-checksum.py", "--check", pkg)
    for item in ("monitor", "scp", "dtb"):
        a, b = os.path.join(out, f".stock-{item}"), os.path.join(out, f".new-{item}")
        tool("toc1-item.py", "--extract", pkg_in, item, a); tool("toc1-item.py", "--extract", pkg, item, b)
        if open(a, "rb").read() != open(b, "rb").read():
            sys.exit(f"the {item} item changed")
        man.append(f"{item:7} {sha(open(b, 'rb').read())}  TrimUI's, unchanged")
    tool("toc1-item.py", "--extract", pkg, "u-boot", os.path.join(out, ".check-u-boot"))
    if open(os.path.join(out, ".check-u-boot"), "rb").read()[:len(u)] != u:
        sys.exit("the package's u-boot item does not read back as ours")
    p = open(pkg, "rb").read()
    man.append(f"package.bin  {sha(p)}  {len(p)} B (TrimUI's {sha(stock)[:16]}..., {len(stock)} B); toc1 checksum fixed and checked")

    # 3. TrimUI's boot-resource with our pictures
    fat16 = load("fat16", "fat16-boot-resource.py")
    old = open(bootres_in, "rb").read()
    tree = fat16.read_tree(old)
    want = {b"BOOTLOGOBMP": "bootlogo.bmp", b"BAT        ": None}
    sub = {b"BATTER~1BMP": "battery_charge.bmp", b"BAT0    BMP": "bat0.bmp", b"LOW_PWR BMP": "low_pwr.bmp"}
    done = []

    def put(items, names, prefix):
        out_items = []
        for lfn, e, body in items:
            key = e[:11]
            if isinstance(body, list) and key == b"BAT        ":
                body = put(body, sub, "bat/")
            elif body is not None and not isinstance(body, list) and names.get(key):
                path = os.path.join(pics, prefix + names[key])
                new = open(path, "rb").read()
                done.append(f"{prefix}{names[key]}  {sha(new)}  {len(new)} B (TrimUI's {len(body)} B)")
                body = new
            out_items.append((lfn, e, body))
        return out_items
    tree2 = put(tree, want, "")
    if len(done) != 4:
        sys.exit(f"replaced {len(done)} of the 4 pictures: {done}")
    new, n = fat16.write_fat16(old, tree2)
    back = fat16.flatten(fat16.read_tree(new))
    if back != fat16.flatten(tree2):
        sys.exit("the new boot-resource does not read back as written")
    kept = {k: v for k, v in fat16.flatten(tree).items() if k in back and back[k] == v}
    open(os.path.join(out, "bootres.fat"), "wb").write(new)
    man.append(f"bootres.fat  {sha(new)}  {len(new)} B, FAT16 of {n} one-sector clusters; {len(kept)} TrimUI entries kept as they were")
    man += ["  " + d for d in done]
    for f in os.listdir(out):
        if f.startswith("."):
            os.remove(os.path.join(out, f))
    open(os.path.join(out, "MANIFEST.txt"), "w").write("\n".join(man) + "\n")
    print("\n".join(man))


if __name__ == "__main__":
    main()
