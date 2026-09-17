#!/usr/bin/env python3
"""Derive a board's device tree source from the SDK's a133-aw3 board.dts (the Zero 28)
and the board's STOCK device tree (decompiled with dtc): the lcd0 panel block, the
simplepad key map, the wlan node and the battery model are taken from the stock tree,
with its numeric pinctrl phandles rewritten to our &pio / &r_pio label form. The
stock trees are inputs (never redistributed); the generated board.dts is ours.

    scripts/make-board-dts.py <stock.dts> <aw3 board.dts> <out board.dts> <board>
"""
import re
import sys

BANKS = "ABCDEFGHIJKL M"  # index -> bank letter; 11 = PL, 12 = PM on r_pio


def load_nodes(text):
    """Return (lines, phandle->node name)."""
    lines = text.split("\n")
    ph, stack = {}, []
    for l in lines:
        s = l.strip()
        if s.endswith("{"):
            stack.append(s[:-1].strip())
        elif s == "};":
            if stack:
                stack.pop()
        m = re.match(r"phandle = <(0x[0-9a-f]+)>;", s)
        if m and stack:
            ph[m.group(1)] = stack[-1]
    return lines, ph


def node(lines, opener):
    i = next(k for k, l in enumerate(lines) if l.strip() == opener)
    out, d = [], 0
    for l in lines[i:]:
        out.append(l)
        d += l.count("{") - l.count("}")
        if d == 0:
            break
    return out


def convert(line, pio, rpio):
    """Rewrite <0xPH bank pin ...> gpio specs to <&pio PX pin ...>; hex numbers to decimal."""
    def gpio(m):
        ph, bank, pin, rest = m.group(1), int(m.group(2), 16), int(m.group(3), 16), m.group(4)
        label = "&pio" if ph == pio else ("&r_pio" if ph == rpio else None)
        if label is None:
            return m.group(0)
        rest = " ".join(str(int(x, 16)) if x != "0xffffffff" else x for x in rest.split())
        return f"<{label} P{BANKS[bank].strip()} {pin} {rest}>"
    line = re.sub(r"<(0x[0-9a-f]+) (0x[0-9a-f]+) (0x[0-9a-f]+) ((?:0x[0-9a-f]+ ?)+)>", gpio, line)
    line = re.sub(r"<(0x[0-9a-f]+)>", lambda m: f"<{int(m.group(1), 16)}>", line)
    return line


def main(stock_path, aw3_path, out_path, board):
    stock = open(stock_path).read()
    slines, ph = load_nodes(stock)
    pio = next(k for k, v in ph.items() if v.startswith("pinctrl@0300b000"))
    rpio = next(k for k, v in ph.items() if v.startswith("pinctrl@07022000"))
    aw3 = open(aw3_path).read().split("\n")

    # 1. lcd0: our node shell, the stock properties, our pinctrl references.
    s_lcd = node(slines, "lcd0@01c0c000 {")
    props = [convert(l.strip(), pio, rpio) for l in s_lcd[1:-1]
             if l.strip().startswith("lcd_") and "phandle" not in l]
    # The stock trees are the boards' ANDROID trees, whose PWM driver takes the
    # opposite polarity convention from the Tina kernel we build: main-zero40's
    # Tina tree drives the same Zero 40 backlight with lcd_pwm_pol = 0, and the
    # Android value of 1 gave an inverted, near-dark backlight under our kernel
    # (2026-09-16). Same BSP convention on the XU20, so both boards get 0.
    props = [re.sub(r"lcd_pwm_pol = <\d+>;", "lcd_pwm_pol = <0>;", p) for p in props]
    props = [re.sub(r"lcd_backlight = <\d+>;", "lcd_backlight = <128>;", p) for p in props]
    i = next(k for k, l in enumerate(aw3) if l.strip().startswith("lcd0: lcd0@01c0c000 {"))
    j = i
    d = 0
    for k in range(i, len(aw3)):
        d += aw3[k].count("{") - aw3[k].count("}")
        if d == 0:
            j = k
            break
    pinctrl = [l for l in aw3[i:j] if l.strip().startswith("pinctrl-")]
    new_lcd = ["\t\tlcd0: lcd0@01c0c000 {",
               f"\t\t\t/* {board}: panel block from the board's stock device tree (oakMOSS make-board-dts.py) */"]
    new_lcd += ["\t\t\t" + p for p in props] + [""] + pinctrl + ["\t\t};"]
    aw3[i:j + 1] = new_lcd

    # 2a. wlan: NOT copied. The stock (Android) node names its regulator as
    # wlan_power = "..." and calls the PL7 line power_en; our sunxi-wlan glue
    # (drivers/misc/sunxi-rf/sunxi-wlan.c) reads wlan_power_num + wlan_powerN and
    # drives only chip_en. Copying the stock node left the Zero 40's XR829
    # unpowered ("wlan_power_num (-1)", SDIO cmd 5 timeouts, 2026-09-16). So the
    # node is built in the Tina form main-zero40 uses, with the stock pins.
    s_wlan = node(slines, "wlan@0 {")
    sp = {}
    for l in s_wlan[1:-1]:
        t = l.strip().rstrip(";")
        if " = " in t:
            k, v = t.split(" = ", 1); sp[k] = v
        elif t and "phandle" not in t:
            sp[t] = None
    power = sp.get("wlan_power1") or sp.get("wlan_power") or '"axp2202-bldo1"'
    def gpio_of(key):
        v = sp.get(key)
        return convert(f"x = {v};", pio, rpio)[4:-1] if v and v.startswith("<") else None
    chip = gpio_of("chip_en") or gpio_of("power_en")
    wl = ["\t\twlan: wlan@0 {", f"\t\t\t/* {board}: pins from the board's stock tree, in the form our sunxi-wlan glue reads */",
          '\t\t\tcompatible    = "allwinner,sunxi-wlan";', "\t\t\tclocks        = <&clk_losc_out>, <&clk_dcxo_out>;",
          "\t\t\tpinctrl-0;", "\t\t\tpinctrl-names;", f"\t\t\twlan_busnum   = {sp.get('wlan_busnum', '<0x1>').replace('0x1', '1')};",
          "\t\t\twlan_power_num = <1>;", f"\t\t\twlan_power1   = {power};", "\t\t\twlan_io_regulator;",
          f"\t\t\twlan_regon    = {gpio_of('wlan_regon')};", f"\t\t\twlan_hostwake = {gpio_of('wlan_hostwake')};",
          (f"\t\t\tchip_en       = {chip};" if chip else "\t\t\tchip_en;"), "\t\t\tpower_en;", '\t\t\tstatus        = "okay";', "\t\t};"]
    i = next(k for k, l in enumerate(aw3) if l.strip() == "wlan: wlan@0 {")
    d = 0
    for k in range(i, len(aw3)):
        d += aw3[k].count("{") - aw3[k].count("}")
        if d == 0:
            j = k
            break
    aw3[i:j + 1] = wl

    # 2b. simplepad: the stock node, converted, in place of ours.
    for opener, ours in (("simplepad {", "simplepad {"),):
        s_node = node(slines, opener)
        i = next(k for k, l in enumerate(aw3) if l.strip() == ours)
        d = 0
        for k in range(i, len(aw3)):
            d += aw3[k].count("{") - aw3[k].count("}")
            if d == 0:
                j = k
                break
        body = []
        for l in s_node[1:-1]:
            if "phandle" in l:
                continue
            t = l.strip()
            if opener.startswith("wlan") and t.startswith("clocks"):
                t = 'clocks        = <&clk_losc_out>, <&clk_dcxo_out>;'   # ours; the stock line is phandles
            body.append(t)
        ind = "\t\t"
        out = [ind + ours, f"{ind}\t/* {board}: from the board's stock device tree */"]
        depth = 1
        for t in body:
            if t == "":
                out.append("")
                continue
            if t == "};":
                depth -= 1
            out.append(ind + "\t" * depth + convert(t, pio, rpio))
            if t.endswith("{"):
                depth += 1
        out.append(ind + "};")
        aw3[i:j + 1] = out

    # 3. framebuffer size: the stock disp node's fb0 geometry (ours is the Zero 28's 480x640).
    for key in ("fb0_width", "fb0_height"):
        val = next(l for l in slines if re.search(rf"\b{key} = <", l))
        val = convert(val.strip(), pio, rpio)
        i = next(k for k, l in enumerate(aw3) if re.search(rf"\b{key}\s*=", l))
        aw3[i] = "\t\t\t" + val
    # 4. battery model.
    for key in ("pmu_battery_rdc", "pmu_battery_cap"):
        val = next(l for l in slines if re.search(rf"\b{key} = <", l))
        val = convert(val.strip(), pio, rpio)
        i = next(k for k, l in enumerate(aw3) if re.search(rf"\b{key} ?=", l))
        aw3[i] = "\t\t\t" + val
    open(out_path, "w").write("\n".join(aw3))
    print(f"{out_path}: lcd0/simplepad/wlan/battery from {stock_path.split('/')[-1]} (pio {pio}, r_pio {rpio})")


if __name__ == "__main__":
    main(*sys.argv[1:5])
