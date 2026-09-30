#!/usr/bin/env python3
"""Name a KDEBUG_MARK suspend-path value (sdk-patches/debug/kdebug-mark.patch).

    scripts/kmark-pm-decode.py <names file> <hex value> [...]

<names file> lists candidate device names, one per line: on the board,
`find /sys/devices | sed 's#.*/##' | sort -u` (dev_name() is each device
directory's name). Values come from the env partition's `bootmark` ('u<hex>' is
what the boot before left in RTC GPR5).

  0x5A00000S   the suspend path reached stage S
  0xDSxhhhhh   stage S, device hhhhhh (FNV-1a of dev_name, 23 bits) started its
               PM callback (x = 0) or returned from it (x = 8, bit 23)
  0xESxhhhhh   stage S, device hhhhhh entered its per-device step (x = 0) or got
               past __pm_runtime_disable() (x = 8); no 0xD mark after it means
               the hang is before the callback (runtime PM, children, wakeup)
  0xFSxhhhhh   stage S, device hhhhhh finished its per-device step (x = 8: failed
               or aborted)
  0x5B0000nn   a point no device or stage mark covers (SUBS below)
  0x5C......   display resume (dev_disp.c disp_resume, disp_lcd.c enable, the XU20
               panel's DSI init table): see decode_disp()
"""
import bisect
import os
import sys

FATAL = {0x63: 'panic() called from', 0x64: 'OOPS (die) at PC', 0x65: 'BAD MODE / SError (die via bad_mode) at PC',
         0x66: 'machine_restart() called from', 0x67: 'machine_power_off() called from', 0x68: 'machine_halt() called from'}


def symbolize_abs(addr):
    path = os.environ.get('KMARK_SYSTEM_MAP')
    if not path:
        return f'{addr:#x}'
    text = [int(l.split()[0], 16) for l in open(path) if l.rstrip().endswith(' _text')][0]
    return symbolize(addr - text)


def symbolize(off):
    """Map an offset from _text to symbol+offset with the System.map named by $KMARK_SYSTEM_MAP."""
    path = os.environ.get('KMARK_SYSTEM_MAP')
    if not path:
        return f'_text+{off:#x} (set KMARK_SYSTEM_MAP=<build>/System.map to name it)'
    syms = []
    text = None
    for line in open(path):
        a, t, n = line.split()[:3]
        a = int(a, 16)
        if n == '_text':
            text = a
        if t in 'tTwW':
            syms.append((a, n))
    syms.sort()
    addr = text + off
    i = bisect.bisect_right([a for a, _ in syms], addr) - 1
    return f'{syms[i][1]}+{addr - syms[i][0]:#x} ({addr:#x})' if i >= 0 else f'{addr:#x}'

STAGES = {
    0x1: 'dpm_suspend_start (prepare + suspend callbacks)',
    0x2: 'dpm_suspend_late',
    0x3: 'dpm_suspend_noirq',
    0x4: 'platform prepare_noirq',
    0x5: 'freeze_enter (s2idle, CPUs idle)',
    0x6: 'disable_nonboot_cpus',
    0x7: 'syscore_suspend',
    0x8: 'suspend_ops->enter: PSCI SYSTEM_SUSPEND into ATF/SCP',
    0x9: 'back from the sleep call (enter / freeze_enter returned)',
    0xa: 'syscore_resume done',
    0xb: 'dpm_resume_noirq',
    0xc: 'dpm_resume_early',
    0xd: 'dpm_resume_end (resume + complete callbacks)',
    0xe: 'all devices resumed',
    0xf: 'console resumed: suspend path finished',
}

SUBS = {
    0x10: 'late suspend: pm_wakeup_pending() -> -EBUSY, the suspend aborts',
    0x21: 'dpm_suspend_late: device loop finished, entering async_synchronize_full()',
    0x22: 'dpm_suspend_late: async_synchronize_full() returned',
    0x23: 'dpm_suspend_late failed: running dpm_resume_early() (0xEc/0xDc marks follow)',
    0x24: 'dpm_suspend_late failed: dpm_resume_early() returned',
    0x25: 'suspend_enter: late suspend failed, going to platform_resume_finish()',
    0x30: 'suspend_enter: entering platform_resume_finish()',
    0x31: 'suspend_enter: platform_resume_finish() returned',
}

DISP = {
    0x5C000100: 'disp_resume: device resume() started', 0x5C000101: 'disp_resume: device resume() returned',
    0x5C000200: 'disp_resume: static config', 0x5C000300: 'disp_resume: lcd enable() started',
    0x5C000301: 'disp_resume: lcd enable() returned', 0x5C000302: 'lcd enable: clocks/pwm/tcon config done',
    0x5C000303: 'lcd enable: open flow finished', 0x5C000400: 'disp_resume: disp_resume_cb() started',
    0x5C000401: 'disp_resume: disp_resume_cb() returned', 0x5C0FFF00: 'panel init: before sunxi_lcd_dsi_clk_enable',
}
OPEN_FLOW = ['lcd_power_on', 'lcd_panel_init (DSI init table)', 'sunxi_lcd_tcon_enable', 'lcd_bl_open']


def decode_disp(v):
    if v in DISP:
        return DISP[v]
    if v >> 12 == 0x5C0E0:
        steps = {1: 'LED gpio', 2: 'lcd_power rail', 3: 'lcd_power1 rail', 4: 'DSI pin cfg',
                 5: 'reset high', 6: 'reset low', 7: 'reset high', 8: 'done'}
        return f'lcd_power_on step {(v >> 8) & 0xf}: {steps.get((v >> 8) & 0xf, "?")} started'
    if v >> 16 == 0x5C0B:
        st = {1: 'regulator_enable entered', 2: 'axp_add_enabler done', 3: 'supply enabled', 4: 'rdev mutex taken',
              5: '_regulator_enable returned', 6: 'ops->enable STARTED', 7: 'ops->enable returned', 8: 'enable delay done'}
        return f'regulator ...{chr(v & 0xff)}: {st.get((v >> 8) & 0xff, "?")}'
    if v >> 12 == 0x5C0D0:
        what = {1: 'regulator_get STARTED', 2: 'regulator_enable STARTED', 3: 'regulator_enable returned'}
        return f'rail ...{chr(v & 0xff)} (disp_sys_power_enable): {what.get((v >> 8) & 0xf, "?")}'
    if v & 0xfffff0fe == 0x5C000010:
        i = (v >> 8) & 0xf
        step = OPEN_FLOW[i] if i < len(OPEN_FLOW) else '?'
        return f'lcd open flow step {i} ({step}) ' + ('returned' if v & 1 else 'STARTED')
    if v >> 20 in (0x5C1, 0x5C2):
        return f'panel DSI init row {(v >> 8) & 0xff} (command {v & 0xff:#04x}) ' + ('returned' if v >> 20 == 0x5C2 else 'STARTED')
    return 'unknown display mark'


def fnv23(name):
    h = 0x811c9dc5
    for b in name.encode():
        h = ((h ^ b) * 0x01000193) & 0xffffffff
    return h & 0x7fffff


IRQ_NAMES = {2: 'IPI CPU_STOP', 0: 'IPI RESCHEDULE', 1: 'IPI CALL_FUNC', 3: 'IPI TIMER', 4: 'IPI IRQ_WORK',
             27: 'arch_timer', 86: 'GPIO port B bank', 100: 'dispaly (lcd/dsi)', 145: 'twi6 (PMIC i2c)',
             129: 'pvrsrvkm (GPU)', 123: 'g2d', 98: 'iommu', 151: 'ppu', 77: '3002000.dma',
             71: 'sunxi-mmc0', 72: 'sunxi-mmc1', 73: 'sunxi-mmc2', 140: 'rtc', 128: 'NMI (PMIC)'}


def load_names(path):
    names = {}
    for n in open(path).read().split():
        names.setdefault(fnv23(n), []).append(n)
    return names


def describe(v, names):
    """One mark value -> text (no hex prefix)."""
    top = v >> 28
    if v >> 16 == 0xb007:
        return f'=== BOOT {v & 0xffff} (ring boot boundary) ==='
    if v >> 24 in (0x69, 0x6d):
        what = 'GPIO bank handler ENTRY' if v >> 24 == 0x69 else 'GPIO bank handler exit'
        return f'{what}: irq bank {(v >> 20) & 0xf} (main PIO: 0 = PB, 1 = PC, ...) pin status {v & 0xfffff:#07x}'
    if v >> 24 in (0x6a, 0x6b):
        what = 'before' if v >> 24 == 0x6a else 'after'
        return f'GPIO bank {(v >> 16) & 0xff} pin {(v >> 8) & 0xff}: {what} its handler (linux irq ...{v & 0xff:#04x})'
    if v >> 24 == 0x6c:
        irq = v & 0x3ff
        return f'irq ID {irq} ({IRQ_NAMES.get(irq, "SPI " + str(irq - 32))}) handler RETURNED'
    if 1 <= v <= 6:
        return f'init hand-off stage {v}'
    if v >> 24 in (0x48, 0x41):
        drv = 'hynitron' if v >> 24 == 0x48 else 'axs15205'
        step = (v >> 16) & 0xff
        named = {0x3a: 'report WORK started', 0x3b: 'report work finished', 0x3c: 'touch INTERRUPT taken'}
        if step in named:
            what = named[step]
        elif step == 0xff:
            what = 'probe error path'
        elif step & 0x80:
            what = f'probe step {step & 0x7f}'
        elif step & 0x40:
            what = f'reset-pulse step {step & 0x3f}'
        else:
            what = f'init step {step}'
        lo = v & 0xffff
        ph = {1: 'started', 2: 'waiting for its IRQ', 3: 'done', 4: 'TIMED OUT', 5: 'START failed', 6: 'bus busy'}
        i2c = f' | bus-1 i2c to {lo >> 8:#04x}: {ph.get(lo & 0xff, "?")}' if lo else ''
        return f'touch ({drv}): {what}{i2c}'
    if (v >> 24) in (0x08, 0x09):
        return f'initcall {symbolize_abs(0xffffff8000000000 | v)}'
    top = v >> 28
    if v >> 8 == 0x5A0000:
        return (f'stage {v & 0xf:x}: {STAGES.get(v & 0xf, "?")}')
    elif top == 0xD:
        s = (v >> 24) & 0xf
        when = 'returned from' if v & 0x800000 else 'STARTED (did not return)'
        dev = names.get(v & 0x7fffff, ['<no name matches>'])
        return (f'stage {s:x} ({STAGES.get(s, "?")}): {when} the PM callback of {" / ".join(dev)}')
    elif v >> 24 in FATAL:
        return (f'FATAL: {FATAL[v >> 24]} {symbolize(v & 0xffffff)}')
    elif v >> 24 == 0x5F:
        b = lambda n: (v >> n) & 1
        hp = v & 0x3ff
        return (f'resume probe phase 1 (irqs masked 20 ms): highest pending irq '
              f'{"none" if hp == 1023 else hp} | timer PPI27 enabled={b(10)} | CNTV_CTL enable={b(11)} '
              f'imask={b(12)} istatus={b(13)} deadline-passed={b(14)} | cpu-if on={b(15)} | '
              f'pending SPIs={(v >> 16) & 0xf}')
    elif v >> 24 == 0x60:
        return (f'resume probe phase 2 (irqs on 20 ms) finished: {(v >> 16) & 0xff} timer irqs '
              f'(~5 expected), {v & 0xffff} irqs total')
    elif v >> 24 == 0x62:
        irq, cnt, p2 = v & 0x3ff, (v >> 10) & 0xfff, (v >> 22) & 1
        irq_names = IRQ_NAMES
        return (f'irq trace: interrupt ID {irq} ({irq_names.get(irq, "see /proc/interrupts: SPI = ID-32")}), '
              f'{cnt}{"+" if cnt == 4095 else ""} irqs since the trace started, probe phase 2 {"done" if p2 else "NOT done"}'
              + ('  -> STORM' if cnt == 4095 and not p2 else ''))
    elif v >> 24 == 0x5E:
        c, jj, ms = (v >> 20) & 0xf, (v >> 12) & 0xff, v & 0xfff
        cpu = {0xf: 'none (-1)', 0xe: 'boot (-2)'}.get(c, str(c))
        return (f'tick probe over a 50 ms busy-wait: jiffies +{jj} (HZ 250 -> ~12), ktime +{ms} ms, '
              f'tick_do_timer_cpu {cpu}' + ('  -> THE TICK IS NOT RUNNING' if jj == 0 and ms >= 40 else ''))
    elif v >> 24 == 0x5D:
        k = v & 0xffffff
        if k == 0xffffff:
            what = 'RTC seconds never changed (loop bound hit)'
        elif k == 0xfffffe:
            what = 'not measured (no resume since boot)'
        else:
            what = f'{k} kticks per RTC second (24000 = 24 MHz, right; ~32 = left on the 32 kHz clock)'
        return (f'system counter rate after resume: {what}')
    elif v >> 16 == 0x4936:
        ph = {1: 'started', 2: 'running (waiting for the IRQ)', 3: 'done', 4: 'TIMED OUT (no completion IRQ in 5 s)',
              5: 'START failed', 6: 'bus busy (9-pulse recovery failed)'}
        return (f's_twi (i2c-6, PMIC bus) transfer (images before 20260929-2007: to address {(v >> 8) & 0xff:#04x}; '
              f'later: by pid ...{(v >> 8) & 0xff:#04x}): {ph.get(v & 0xff, "?")}')
    elif v >> 24 == 0x5C:
        return (f'{decode_disp(v)}')
    elif v >> 8 == 0x5B0000:
        return (f'{SUBS.get(v & 0xff, "unknown sub-mark")}')
    elif top == 0xF:
        s = (v >> 24) & 0xf
        when = 'FAILED/ABORTED' if v & 0x800000 else 'finished'
        dev = names.get(v & 0x7fffff, ['<no name matches>'])
        return (f'stage {s:x} ({STAGES.get(s, "?")}): {when} the per-device step of {" / ".join(dev)}')
    elif top == 0xE:
        s = (v >> 24) & 0xf
        when = 'past __pm_runtime_disable() in' if v & 0x800000 else 'ENTERED (runtime PM not yet disabled)'
        dev = names.get(v & 0x7fffff, ['<no name matches>'])
        return (f'stage {s:x} ({STAGES.get(s, "?")}): {when} the per-device step of {" / ".join(dev)}')
    else:
        return 'not a known mark'


def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__)
    names = load_names(argv[1])
    for arg in argv[2:]:
        v = int(arg, 16)
        print(f'{v:#010x}  {describe(v, names)}')


if __name__ == '__main__':
    main(sys.argv)
