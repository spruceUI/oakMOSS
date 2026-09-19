#!/usr/bin/env python3
"""Derive a board's device tree source from the SDK's a133-aw3 board.dts (the Zero 28)
and the board's STOCK device tree (decompiled with dtc): the lcd0 panel block, the
simplepad key map, the wlan node, the battery model and the twi1 touch controller
node are taken from the stock tree,
with its numeric pinctrl phandles rewritten to our &pio / &r_pio label form. The
stock trees are inputs (never redistributed); the generated board.dts is ours.

    scripts/make-board-dts.py <stock.dts> <aw3 board.dts> <out board.dts> <board>
"""
import re
import sys

BANKS = "ABCDEFGHIJKL M"  # index -> bank letter; 11 = PL, 12 = PM on r_pio
TOUCH_FLIP_X = {"xu20"}   # digitizer X axis mounted opposite the display (measured)


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


def node_by_phandle(lines, phv):
    """The node whose own phandle property is phv (walk back from that line to its opener)."""
    p = next(k for k, l in enumerate(lines) if l.strip() == f"phandle = <{phv}>;")
    depth = 0
    for k in range(p, -1, -1):
        t = lines[k].strip()
        if t == "};":
            depth += 1
        elif t.endswith("{"):
            if depth == 0:
                return node(lines[k:], t)
            depth -= 1
    raise KeyError(phv)


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
    # lcd_pwm_pol is taken from the stock tree unchanged. It was briefly forced to 0
    # here (2026-09-16) after a dim Zero 40 backlight was read as inversion; that was
    # wrong. Measured on 2026-09-17 across four A133P boards: spruce and the display
    # driver map brightness identically everywhere (setting 2 -> 29, setting 9 -> 226,
    # the same on the TrimUI Smart Pro whose backlight is correct), so the direction of
    # the curve is decided purely by this polarity against the panel's LED driver. With
    # 0 both boards ran inverted, and MagicX's own firmware ships 1 on both panels.
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
    # 5. twi1 + the panel's touch controller. The stock trees wire twi1 to PB4/PB5
    #    (the Zero 28 tree: PH2/PH3) and hang the touch controller off it: the
    #    XU20's Hynitron CST340 at 0x5a (node "ctp": Allwinner ctp_* props read
    #    by init-input.c plus hynitron,* read by the driver), the Zero 40's
    #    AXS15205 at 0x3b (touch,irq-gpio). Pins from the stock pin nodes, twi1
    #    enabled, the stock child node carried verbatim with its gpio specs
    #    converted. The Zero 28 keeps its own (touchless) tree.
    s_twi = node(slines, "twi@0x05002400 {")
    for idx, ours in ((0, "twi1_pins_a: twi1@0 {"), (1, "twi1_pins_b: twi1@1 {")):
        phv = re.search(rf"pinctrl-{idx} = <(0x[0-9a-f]+)>;", "\n".join(s_twi)).group(1)
        pins = next(l.strip() for l in node_by_phandle(slines, phv) if l.strip().startswith("allwinner,pins"))
        i = next(k for k, l in enumerate(aw3) if l.strip() == ours)
        j = next(k for k in range(i, len(aw3)) if aw3[k].strip().startswith("allwinner,pins"))
        aw3[j] = "\t\t\t\t" + pins
    k0 = next(k for k, l in enumerate(s_twi) if k > 0 and l.strip().endswith("{"))
    child = node(s_twi[k0:], s_twi[k0].strip())
    out = ["\t\ttwi1: twi@0x05002400{", "\t\t\tclock-frequency = <200000>;",
           "\t\t\tpinctrl-0 = <&twi1_pins_a>;", "\t\t\tpinctrl-1 = <&twi1_pins_b>;",
           '\t\t\tstatus = "okay";', "",
           f"\t\t\t/* {board}: touch controller node from the board's stock device tree */"]
    depth = 1
    for l in child:
        t = l.strip()
        if not t or "phandle" in t:
            continue
        if t == "};":
            depth -= 1
        c = t if t.startswith("reg = ") else convert(t, pio, rpio)   # reg stays hex
        # The touch flags describe how the digitizer is mounted relative to the
        # panel, so they are a per-board hardware fact rather than a stock value to
        # copy. Measured 2026-09-17: the XU20's X axis runs opposite its display
        # (a top-left touch landed top-right) while its Y is already correct, and
        # the Zero 40 needs neither flip. Flipping X here puts the driver's output
        # in the panel's own frame, which is what PyUI's rotation inverse expects.
        if board in TOUCH_FLIP_X and re.match(r"ctp_revert_x_flag = <", c):
            c = re.sub(r"<\d+>", "<1>", c)
        out.append("\t\t" + "\t" * depth + c)
        if t.endswith("{"):
            depth += 1
    out.append("\t\t};")
    i = next(k for k, l in enumerate(aw3) if l.strip().startswith("twi1: twi@0x05002400"))
    d = 0
    for k in range(i, len(aw3)):
        d += aw3[k].count("{") - aw3[k].count("}")
        if d == 0:
            j = k
            break
    aw3[i:j + 1] = out

    # 6. lcd power rails as disp supplies. The disp driver enables each lcd_powerN
    #    name through regulator_get(disp dev, name) (CONFIG_SUNXI_REGULATOR_DT), which
    #    needs a "<name>-supply" phandle on the disp node; a missing one yields a
    #    dummy regulator, nothing holds the rail, and the kernel's unused-regulator
    #    sweep switches it off ~3.8 s into boot. The Zero 28 tree only knows cldo4;
    #    the stock trees name cldo2 as lcd_power and the touch controller's I2C
    #    lines sat on that dead rail (Zero 40, 2026-09-17: every frame read failed).
    names = re.findall(r'lcd_power\d* = "(\w+)";', "\n".join(props))
    di = next(k for k, l in enumerate(aw3) if l.strip().startswith("disp: disp@"))
    dj = next(k for k in range(di, len(aw3)) if aw3[k].strip() == "};")
    have = {m.group(1): m.group(2) for m in (re.match(r'(\w+)-supply = <&(\w+)>;', aw3[k].strip()) for k in range(di, dj)) if m}
    for name in names:
        if name in have:
            continue
        label = next((lab for lab in (f"reg_{name}", name) if re.search(rf"\b{lab}:", "\n".join(aw3))), None)
        if label is None:
            raise SystemExit(f"{board}: no regulator label for lcd power rail {name}")
        aw3.insert(dj, f"\t\t\t{name}-supply = <&{label}>;\t/* {board}: lcd_power rail from the stock tree */")
        dj += 1
    # 7. CPU supply from the stock tree. The SDK's reference tree feeds the CPU from a
    #    TCS4838 buck (twi6 0x41); MagicX's boards feed it from the PMIC's dcdc1 and the
    #    TCS4838 does not answer on them. Left as the reference had it, the kernel scaled
    #    the CPU to 1.8 GHz while every voltage request went to the phantom and the real
    #    rail stayed at U-Boot's 0.94 V (first taken for the 2026-09-17/18 boot stall,
    #    which was the built-in touch drivers). The stock cpu-supply phandle is resolved to its regulator name and
    #    mapped to our reg_<name> label; when it is not the TCS, the tcs node is disabled
    #    so its driver stops wedging the PMIC bus (5 s xfer timeouts at boot).
    sup = re.search(r"cpu-supply = <(0x[0-9a-f]+)>;", stock).group(1)
    reg = next(l.strip() for l in node_by_phandle(slines, sup) if l.strip().startswith("regulator-name"))
    rname = re.search(r'"axp2202-(\w+)"|"(\w+)"', reg)
    rname = rname.group(1) or rname.group(2)
    ci = next(k for k, l in enumerate(aw3) if l.strip().startswith("cpu-supply = "))
    aw3[ci] = f"\tcpu-supply = <&reg_{rname}>;\t/* {board}: the CPU rail per the board's stock tree (oakMOSS) */"
    if not rname.startswith("tcs"):
        ti = next(k for k, l in enumerate(aw3) if l.strip().endswith("tcs@41 {"))
        ts = next(k for k in range(ti, len(aw3)) if aw3[k].strip() == 'status = "okay";')
        aw3[ts] = f'\t\t\t\tstatus = "disabled";\t/* {board}: no TCS4838 answers here; the CPU rail is {rname} (oakMOSS) */'
    open(out_path, "w").write("\n".join(aw3))
    print(f"{out_path}: lcd0/simplepad/wlan/battery/twi1+touch/lcd-power-supplies/cpu-supply from {stock_path.split('/')[-1]} (pio {pio}, r_pio {rpio})")


if __name__ == "__main__":
    main(*sys.argv[1:5])
