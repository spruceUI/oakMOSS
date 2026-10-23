#!/usr/bin/env python3
"""Derive the Powkiddy V90S/V20 sys_config.fex: the Zero 28's file with every value that
differs on these boards taken from their STOCK device tree (decompiled with dtc).

    scripts/make-sys-config-powkiddy.py <stock.dts> <zero28 sys_config.fex> <out sys_config.fex>

The SDK pack merges sys_config.fex into the device tree (dtc -F), and the U-Boot on
either chain reads the merged sections from it, so a Zero 28 value here would reach
these boards even behind their stock boot chain. The stock tree carries the stock
firmware's own merged sections (/soc@03000000/<section>, /dram), which is where every
replaced value below comes from; nothing is typed in. What differs (2026-10-23):

- power_sply: the stock rail list: bldo1 on at 3.3 V (port G), bldo3 and cldo4 at
  2.8 V (the Zero 28's 3.3 V), aldo3 kept on in standby, no aldo1 or bldo4;
- jtag_para off: its pins PH9-PH12 are the d-pad here;
- gpio_bias: ports C and L at 1.8 V;
- dram_para (DDR3 at 576 MHz) and dram_select_para: the stock DRAM, for the SDK chain;
- target, platform, auto_print, card2_boot_para: the stock values.
"""
import re
import sys

POWER_KEYS_ORDER = ("dcdc1_vol", "dcdc2_vol", "dcdc3_vol", "dcdc4_vol", "aldo1_vol", "aldo2_vol",
                    "aldo3_vol", "aldo4_vol", "bldo1_vol", "bldo2_vol", "bldo3_vol", "bldo4_vol",
                    "cldo1_vol", "cldo2_vol", "cldo3_vol", "cldo4_vol", "cpusldo_vol",
                    "dcdc1_mode", "dcdc2_mode", "ntc_status")


def stock_nodes(path):
    """{node name: {prop: value text}} for /dram and the /soc@03000000/<section> nodes."""
    nodes, stack = {}, []
    for raw in open(path):
        line = raw.strip()
        m = re.match(r'^([^\s{}=;]+) \{$', line)
        if m:
            stack.append(m.group(1))
            continue
        if line == "};":
            stack.pop()
            continue
        m = re.match(r'^([^\s=]+) = (.*);$', line)
        if m and (stack == ["/", "dram"] or (len(stack) == 3 and stack[:2] == ["/", "soc@03000000"])):
            nodes.setdefault(stack[-1], {})[m.group(1)] = m.group(2)
    return nodes


def cell(v):
    m = re.fullmatch(r'<(0x[0-9a-f]+)>', v)
    if not m:
        sys.exit(f"not a single cell: {v}")
    n = int(m.group(1), 16)
    return n - (1 << 32) if n >= 0x80000000 else n


def main(stock, base, out):
    st = stock_nodes(stock)
    for need in ("dram", "power_sply", "target", "gpio_bias", "jtag_para", "dram_select_para",
                 "platform", "card2_boot_para"):
        if need not in st:
            sys.exit(f"{stock}: no {need} node")
    lines = open(base, newline="").read().split("\n")

    def section(name):
        first = lines.index(f"[{name}]")
        last = next((i for i in range(first + 1, len(lines)) if lines[i].startswith("[")), len(lines))
        return first, last

    def set_key(name, key, value):
        first, last = section(name)
        for i in range(first + 1, last):
            m = re.match(rf'^(\s*{re.escape(key)}\s*=\s*)', lines[i])
            if m:
                lines[i] = m.group(1) + str(value)
                return
        lines.insert(last, f"{key} = {value}")

    def drop_key(name, key):
        first, last = section(name)
        for i in range(first + 1, last):
            if re.match(rf'^\s*{re.escape(key)}\s*=', lines[i]):
                del lines[i]
                return
        sys.exit(f"[{name}] has no {key}")

    # power_sply: the stock list exactly, in the base's order
    first, last = section("power_sply")
    ps = st["power_sply"]
    body = [f"{k:<26} = {cell(ps[k])}" for k in POWER_KEYS_ORDER if k in ps]
    unknown = [k for k in ps if k not in POWER_KEYS_ORDER and k not in ("device_type", "phandle", "linux,phandle")]
    if unknown:
        sys.exit(f"power_sply: keys not modelled: {unknown}")
    keep = [l for l in lines[first + 1:last] if not re.match(r'^\s*[a-z]', l)]
    lines[first + 1:last] = body + keep

    for name, keys in (("target", ("boot_clock", "storage_type", "power_mode", "advert_enable", "battery_exist")),
                       ("gpio_bias", ("pc_bias", "pl_bias")),
                       ("jtag_para", ("jtag_enable",)),
                       ("platform", ("debug_mode",)),
                       ("card2_boot_para", ("card_line", "sdc_ex_dly_used"))):
        for k in keys:
            set_key(name, k, cell(st[name][k]))
    set_key("auto_print", "auto_print_used", 0)   # stock: auto_print disabled

    # dram_select_para: the stock has no GPADC/GPIO selection of a DRAM variant
    for k in ("gpadc_channel", "select_gpio0", "index_ddr4_lijing"):
        if k in st["dram_select_para"]:
            sys.exit(f"dram_select_para: stock sets {k}; not modelled")
        drop_key("dram_select_para", k)

    # dram_para: the stock /dram node, in the SDK's key order (boot0's header order)
    first, last = section("dram_para")
    dram = st["dram"]
    for i in range(first + 1, last):
        m = re.match(r'^(\s*(dram_[a-z0-9_]+)\s*=\s*)', lines[i])
        if not m:
            continue
        k = m.group(2)
        if k not in dram:
            sys.exit(f"dram_para: {k} not in the stock /dram node")
        v = cell(dram[k])
        lines[i] = m.group(1) + (str(v) if k in ("dram_clk", "dram_type") else f"0x{v & 0xffffffff:08x}")

    head = ["; Powkiddy V90S/V20: the Zero 28's sys_config.fex with the stock tree's values, made by",
            "; scripts/make-sys-config-powkiddy.py. Generated: do not edit by hand.", ""]
    open(out, "w", newline="").write("\n".join(head + lines))
    print(f"{out}: power_sply {len(body)} keys from stock, dram {cell(dram['dram_clk'])} MHz type "
          f"{cell(dram['dram_type'])}, jtag off, gpio_bias 1.8 V, target power_mode {cell(st['target']['power_mode'])}")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
