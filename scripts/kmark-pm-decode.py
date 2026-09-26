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
"""
import sys

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


def fnv23(name):
    h = 0x811c9dc5
    for b in name.encode():
        h = ((h ^ b) * 0x01000193) & 0xffffffff
    return h & 0x7fffff


def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__)
    names = {}
    for n in open(argv[1]).read().split():
        names.setdefault(fnv23(n), []).append(n)
    for arg in argv[2:]:
        v = int(arg, 16)
        top = v >> 28
        if v >> 8 == 0x5A0000:
            print(f'{v:#010x}  stage {v & 0xf:x}: {STAGES.get(v & 0xf, "?")}')
        elif top == 0xD:
            s = (v >> 24) & 0xf
            when = 'returned from' if v & 0x800000 else 'STARTED (did not return)'
            dev = names.get(v & 0x7fffff, ['<no name matches>'])
            print(f'{v:#010x}  stage {s:x} ({STAGES.get(s, "?")}): {when} the PM callback of {" / ".join(dev)}')
        else:
            print(f'{v:#010x}  not a suspend-path mark (initcall address, hand-off stage or touch step)')


if __name__ == '__main__':
    main(sys.argv)
