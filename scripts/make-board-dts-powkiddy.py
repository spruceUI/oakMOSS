#!/usr/bin/env python3
"""Derive the Powkiddy V90S or V20 board.dts from the boards' STOCK device tree,
decompiled with dtc (`dtc -I dtb -O dts`): one tree serves both boards on stock.

    scripts/make-board-dts-powkiddy.py <stock.dts> <out board.dts> <v90s|v20>

Each board from ITS OWN stock tree (decompiled with dtc or research/.../dtb2dts.py): the V90S card's
(cache .../powkiddy-v90s/pkg/stock.dts) and, since 2026-10-25, a real V20 card's (cache
.../powkiddy-v20-card/pkg/stock.dts). Knulli's "V20" copy is the V90S's tree; the V20's own differs in DRAM
(504 MHz), battery, thermal trips, panel timing, USB OTG and a MENU button (research README, section 1a).

Unlike scripts/make-board-dts.py (the MagicX boards, grafted onto the SDK's a133-aw3
tree), this keeps the stock tree whole: it is a complete 4.9 Tina tree for this exact
board, and our kernel binds every node in it except the vendor's board check
(sw2001), the hardware-version strap and the disabled rgp-keys and gslX680 nodes.
Only the joypad is new code (sdk-patches/tree/151, the stock "adc-joypad" binding)
and the panel driver (150). The edits:

- the joypad's name, per board, so spruce and SDL can tell the boards apart;
- the face buttons on the A133P line's codes (A 305, B 304, X 308, Y 307), as
  make-board-dts.py's FACE_CODE_SWAP does for MagicX: the stock tree labels
  A as 304, B 305, X 307, Y 308;
- V90S: no stick multiplexer (it has no sticks; the stock tree describes the V20's);
- V20 (its own tree already has L3/R3 on PD21/PD20 and no rumble; both are checked): MENU (PH7, stock
  BTN_TRIGGER_HAPPY1) and FAV (the V90S's Mode GPIO, stock BTN_TRIGGER_HAPPY2) both send BTN_MODE, spruce's
  menu key, until a unit says which one it should be (user, 2026-10-25); pwm2 off so it leaves PD20 alone;
  the charge voltage 4350 -> 4200 mV (user, 2026-10-25: 4.20 V until a unit shows the cell); its own panel
  timing (24 MHz, 820 x 504, 58.07 Hz) kept: the V90S's 60 Hz edit cannot be reached at 24 MHz;
- the vendor board-check node disabled (we build no driver for it);
- bldo1 always on: it feeds port G (L1/R1/L2/R2 and the second card slot), and the
  stock tree lists it only as the panel's third rail, so the unused-regulator sweep
  could switch it off (Knulli's 5.15 tree does the same);
- V90S: the panel's vertical total 514 -> 506 lines (front porch 18 -> 10): the stock timing
  runs the V90S at 59.07 Hz (disp irq count, 2026-10-24), which is 60.0 Hz at 506.

The stock tree is an input (never redistributed); the generated board.dts is ours.
"""
import re
import sys

NAMES = {"v90s": "Powkiddy V90S Gamepad", "v20": "Powkiddy V20 Gamepad"}
FACE_CODES = {"Button A": (0x130, 0x131), "Button B": (0x131, 0x130),
              "Button X": (0x133, 0x134), "Button Y": (0x134, 0x133)}
AMUX_PROPS = ("amux-count", "amux-a-gpios", "amux-b-gpios", "amux-en-gpios")
RUMBLE_PROPS = ("rumble_used", "pwm-id", "pwm-period", "rumble-boost-weak",
                "rumble-boost-strong", "invert-rumble")
BTN_THUMBL, BTN_THUMBR = 0x13d, 0x13e
STOCK_VT, PANEL_VT = 0x202, 0x1fa
V20_PANEL = {"lcd_dclk_freq": 0x18, "lcd_ht": 0x334, "lcd_vt": 0x1f8}     # the V20 tree's own, kept
V20_MENU = {"MENU": 0x2c0, "FAV": 0x2c1}       # stock codes, both -> BTN_MODE
BTN_MODE, CHGVOL_STOCK_V20, CHGVOL = 0x13c, 0x10fe, 0x1068


def node_span(lines, header, start=0, end=None):
    """(first, last) line index of the node whose opening line is `header`."""
    end = len(lines) if end is None else end
    first = next(i for i in range(start, end) if lines[i].strip() == header)
    depth = 0
    for i in range(first, end):
        depth += lines[i].count("{") - lines[i].count("}")
        if depth == 0:
            return first, i
    sys.exit(f"node {header!r}: no closing brace")


def prop_index(lines, first, last, name):
    """Line index of property `name` directly in the node at first..last, or None."""
    depth = 0
    for i in range(first + 1, last):
        s = lines[i].strip()
        if depth == 0 and (s.startswith(name + " =") or s == name + ";"):
            return i
        depth += lines[i].count("{") - lines[i].count("}")
    return None


def set_prop(lines, first, last, name, value):
    i = prop_index(lines, first, last, name)
    if i is None:
        sys.exit(f"{lines[first].strip()}: no {name}")
    ind = lines[i][:len(lines[i]) - len(lines[i].lstrip())]
    lines[i] = f"{ind}{name} = {value};"


def main(src, out, board):
    if board not in NAMES:
        sys.exit("board: v90s | v20")
    lines = open(src).read().split("\n")
    if not lines[0].startswith("/dts-v1/;"):
        sys.exit(f"{src}: not dtc output")

    # the joypad
    first, last = node_span(lines, "adc_joystick {")
    if '"adc-joypad"' not in "\n".join(lines[first:last]):
        sys.exit("adc_joystick is not the stock adc-joypad node")
    set_prop(lines, first, last, "joypad-name", f'"{NAMES[board]}"')
    seen = set()
    for i in range(first, last):
        m = re.match(r'\s*button@\d+ \{', lines[i])
        if not m:
            continue
        bf, bl = node_span(lines, lines[i].strip(), i, last + 1)
        body = "\n".join(lines[bf:bl])
        lab = re.search(r'lable = "([^"]+)"', body)
        if lab and lab.group(1) in FACE_CODES:
            stock, ours = FACE_CODES[lab.group(1)]
            j = prop_index(lines, bf, bl, "linux,code")
            if lines[j].strip() != f"linux,code = <{stock:#04x}>;":
                sys.exit(f"{lab.group(1)}: {lines[j].strip()}, expected the stock code {stock:#x}")
            lines[j] = lines[j].replace(f"<{stock:#04x}>", f"<{ours:#04x}>")
            seen.add(lab.group(1))
    if seen != set(FACE_CODES):
        sys.exit(f"face buttons found: {sorted(seen)}")
    pio = re.search(r'gpios = <(0x[0-9a-f]+) ', "\n".join(lines[first:last])).group(1)

    if board == "v90s":
        for name in AMUX_PROPS:
            i = prop_index(lines, first, last, name)
            if i is None:
                sys.exit(f"adc_joystick: no {name} to drop")
            del lines[i]
            last -= 1
    else:
        for name in RUMBLE_PROPS:
            if prop_index(lines, first, last, name) is not None:
                sys.exit(f"adc_joystick has {name}: not the V20's own tree (the V90S's has rumble)")
        buttons = []          # (lable, gpios, linux,code) of each button node, whatever their order
        for i in range(first, last):
            if re.match(r'\s*button@\d+ \{', lines[i]):
                bf, bl = node_span(lines, lines[i].strip(), i, last + 1)
                body = "\n".join(lines[bf:bl])
                get = lambda k: (re.search(rf'\b{k} = ([^;]+);', body) or [None, None])[1]
                buttons.append((get("lable"), get("gpios"), get("linux,code")))
        for lab, pin, code in (("BTN_THUMBL", 0x15, BTN_THUMBL), ("BTN_THUMBR", 0x14, BTN_THUMBR)):
            want = (f'"{lab}"', f"<{pio} 0x03 {pin:#04x} 0x00 0x01 0x01 0x00>", f"<{code:#05x}>")
            if want not in buttons:
                sys.exit(f"adc_joystick: no {lab} on PD{pin} with code {code:#x}: not the V20's own tree")
        mapped = set()
        for i in range(first, last):
            if not re.match(r'\s*button@\d+ \{', lines[i]):
                continue
            bf, bl = node_span(lines, lines[i].strip(), i, last + 1)
            lab = re.search(r'lable = "([^"]+)"', "\n".join(lines[bf:bl]))
            if lab and lab.group(1) in V20_MENU:
                j = prop_index(lines, bf, bl, "linux,code")
                if lines[j].strip() != f"linux,code = <{V20_MENU[lab.group(1)]:#05x}>;":
                    sys.exit(f"{lab.group(1)}: {lines[j].strip()}, expected the stock code {V20_MENU[lab.group(1)]:#x}")
                set_prop(lines, bf, bl, "linux,code", f"<{BTN_MODE:#05x}>")
                mapped.add(lab.group(1))
        if mapped != set(V20_MENU):
            sys.exit(f"MENU/FAV found: {sorted(mapped)}: not the V20's own tree")
        # the charge voltage: 4.20 V until a unit shows the cell
        cf, cl = node_span(lines, "bat-power-supply {")
        j = prop_index(lines, cf, cl, "pmu_init_chgvol")
        if j is None or lines[j].strip() != f"pmu_init_chgvol = <{CHGVOL_STOCK_V20:#06x}>;":
            sys.exit(f"bat-power-supply: {lines[j].strip() if j is not None else 'no pmu_init_chgvol'}, expected the V20's {CHGVOL_STOCK_V20:#x}")
        set_prop(lines, cf, cl, "pmu_init_chgvol", f"<{CHGVOL:#06x}>")

    # pwm2 on the V20: PD20 is R3
    if board == "v20":
        pf, pl = node_span(lines, "pwm2@0300a000 {")
        if prop_index(lines, pf, pl, "status") is not None:
            set_prop(lines, pf, pl, "status", '"disabled"')
        else:
            lines.insert(pl, '\t\t\tstatus = "disabled";')

    # the vendor's board check
    sf, sl = node_span(lines, "sw2001@3C {")
    set_prop(lines, sf, sl, "status", '"disabled"')

    # bldo1: port G
    rf, rl = node_span(lines, "bldo1 {")
    for name in ("regulator-boot-on", "regulator-always-on"):
        if prop_index(lines, rf, rl, name) is None:
            lines.insert(rl, f"\t\t\t\t\t\t{name};")
            rl += 1

    # the panel: 60 Hz on the V90S; the V20 keeps its own timing (checked)
    lf, ll = node_span(lines, "lcd0@01c0c000 {")
    if board == "v90s":
        j = prop_index(lines, lf, ll, "lcd_vt")
        if j is None or lines[j].strip() != f"lcd_vt = <{STOCK_VT:#05x}>;":
            sys.exit(f"lcd0: {lines[j].strip() if j is not None else 'no lcd_vt'}, expected the stock {STOCK_VT:#x}")
        set_prop(lines, lf, ll, "lcd_vt", f"<{PANEL_VT:#05x}>")
    else:
        for name, v in V20_PANEL.items():
            j = prop_index(lines, lf, ll, name)
            if j is None or lines[j].strip() != f"{name} = <{v:#04x}>;":
                sys.exit(f"lcd0: {lines[j].strip() if j is not None else 'no ' + name}, expected the V20's {v:#x}")

    head = ["/*",
            f" * Powkiddy {board.upper()} board tree for oakMOSS: the stock tree (decompiled) with the",
            f" * edits in scripts/make-board-dts-powkiddy.py. Generated: do not edit by hand.",
            " */"]
    open(out, "w").write("\n".join(lines[:1] + head + lines[1:]))
    print(f"{out}: {board}, joypad \"{NAMES[board]}\", face codes on the A133P convention, "
          f"{'no stick mux' if board == 'v90s' else 'its own L3/R3, MENU and FAV both BTN_MODE, pwm2 off, charge 4200 mV'}, "
          f"sw2001 off, bldo1 always on, "
          f"{f'panel vt {PANEL_VT} (60 Hz)' if board == 'v90s' else 'its own panel timing (58.07 Hz)'}")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
