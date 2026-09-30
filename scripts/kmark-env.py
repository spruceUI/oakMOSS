#!/usr/bin/env python3
"""Prepare an SDK-chain debug image (KDEBUG_MARK=1) to keep its last mark across a reset.

    scripts/kmark-env.py <sd1.img> <mkenvimage>

Both copies of the image's U-Boot environment get two changes: the kernel command line
gains oakmoss_mark=0x07000114 (RTC general-purpose register 5, where the debug patch writes
its marks), and bootcmd first appends that register to the env variable `bootmark`
('u' + the value), clears it and saves the env. After a freeze and a reset, read the
last value on the board with `strings /dev/mmcblk0p2 /dev/mmcblk0p3 | grep ^bootmark=`
(the env is redundant: the newer copy alternates) and name it with
scripts/kmark-pm-decode.py. Register 4 (0x07000110) is never written: clearing it from
U-Boot stopped both MagicX boards in U-Boot (2026-09-18). mkenvimage is the SDK's
(out/host/bin/mkenvimage; scripts/lib.sh mkenvimage_tool)."""
import json, os, subprocess, sys, tempfile, zlib
img, mkenv = sys.argv[1:3]
parts = {p["name"]: p for p in json.loads(subprocess.check_output(["sfdisk", "-J", img]))["partitiontable"]["partitions"]}
SIZE = 131072
with open(img, "rb") as f:
    f.seek(parts["env"]["start"] * 512); raw = f.read(SIZE)
assert zlib.crc32(raw[5:]) & 0xffffffff == int.from_bytes(raw[:4], "little"), "env CRC (redundant layout) mismatch"
kv = {}
for p in raw[5:].split(b"\0"):
    if not p: break
    k, v = p.decode().split("=", 1); kv[k] = v
assert "oakmoss_mark" not in kv["setargs_mmc"]
kv["setargs_mmc"] += " oakmoss_mark=0x07000114"
kv["bootcmd"] = "setexpr.l kmark *0x07000114; mw.l 0x07000114 0; setenv bootmark ${bootmark}u${kmark}; saveenv; run setargs_mmc boot_normal"
kv["bootmark"] = ""
with tempfile.TemporaryDirectory() as t:
    txt = os.path.join(t, "env.txt"); out = os.path.join(t, "env.bin")
    open(txt, "w").write("".join(f"{k}={v}\n" for k, v in kv.items()))
    subprocess.run([mkenv, "-r", "-s", str(SIZE), "-o", out, txt], check=True)
    new = open(out, "rb").read(); assert len(new) == SIZE
with open(img, "r+b") as f:
    for name in ("env", "env-redund"):
        f.seek(parts[name]["start"] * 512); f.write(new)
print("bootcmd:", kv["bootcmd"]); print("setargs_mmc ends:", kv["setargs_mmc"][-60:])
