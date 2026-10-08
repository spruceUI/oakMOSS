#!/bin/sh
# oakMOSS debug image: one record per boot of how it started and how the boot before ended.
# Usage: oakmoss-debug.sh boot | late | shutdown   (run by /etc/init.d/oakmoss-debug)
D=/mnt/UDISK/oakmoss-debug
CARD=/mnt/SDCARD/oakmoss-debug
CUR=/tmp/oakmoss-debug.cur
KEEP=30

now() { date '+%Y-%m-%d %H:%M:%S'; }
up() { cut -d' ' -f1 /proc/uptime; }
knob() { [ -w "$1" ] && echo "$2" > "$1"; }
rec() { printf '%s/boot-%04d' "$D" "$1"; }

# Nothing this script writes carries the serial number, MAC addresses or network names.
mask() {
	h='[0-9A-Fa-f][0-9A-Fa-f]'
	sed -e 's/androidboot\.serialno=[^ ]*/androidboot.serialno=MASKED/g' \
	    -e "s/$h:$h:$h:$h:$h:$h/xx:xx:xx:xx:xx:xx/g" \
	    -e '/[Ss][Ss][Ii][Dd]\|[Pp][Ss][Kk]\|[Pp]assphrase\|[Pp]assword/s/.*/[line removed: network settings]/'
}

arg() {	# arg <name>: the value of a kernel argument
	for a in $(cat /proc/cmdline); do
		case $a in "$1="*) echo "${a#*=}"; return ;; esac
	done
}

pmic() {	# AXP2202 registers through the driver's debug node: a value under 0x100 only selects
	n=/sys/class/axp/axp_reg
	[ -w $n ] || { echo "(no $n)"; return; }
	for r in 00 01 03 04 05 06 08 0a 0b 0c 0f 10 12 13 14 15 16 17 18 20 21 22 23 24 25 26 27 f0; do
		echo $r > $n && cat $n
	done
}

supplies() {
	for s in /sys/class/power_supply/*; do
		[ -f "$s/uevent" ] && { echo "[${s##*/}]"; cat "$s/uevent"; }
	done
}

procs() {	# names only: command lines can carry settings
	for p in /proc/[0-9]*; do echo "${p#/proc/} $(cat "$p/comm" 2>/dev/null)"; done
}

mark_name() {	# a coarse name for an RTC GPR5 mark; scripts/kmark-pm-decode.py has the detail
	case $1 in
	""|none) echo "not passed: not a debug U-Boot" ;;
	0x00000000) echo "empty: the RTC lost power, or the boot before was not a debug image" ;;
	0x0000000[1-5]) echo "kernel init hand-off stage ${1#0x0000000}: stopped before userland" ;;
	0x00000006) echo "userland started and nothing was marked after: crash, hang or power loss there" ;;
	0x75000001) echo "U-Boot stopped after board init, before booting the kernel" ;;
	0x75000002) echo "U-Boot booted the kernel, which wrote no mark" ;;
	0x63*) echo "kernel panic" ;;
	0x64*) echo "kernel oops (die)" ;;
	0x65*) echo "SError or bad exception" ;;
	0x66*) echo "kernel restart (machine_restart): an ordinary reboot got this far" ;;
	0x67*) echo "kernel power-off (machine_power_off)" ;;
	0x68*) echo "kernel halt (machine_halt)" ;;
	0x41*|0x48*|0x49*) echo "touch driver step or its I2C transfer" ;;
	0x5[a-f]*|0x[d-f]*) echo "suspend or resume path" ;;
	0x62*|0x69*|0x6[a-d]*) echo "interrupt trace" ;;
	0x0[89]*) echo "kernel initcall: the boot stopped in driver init" ;;
	*) echo "other" ;;
	esac
}

pwron_name() {
	case $1 in
	0x01) echo "power key" ;; 0x02) echo "IRQ pin" ;; 0x04) echo "USB power plugged in" ;;
	0x08) echo "battery charged back up to 3.3 V" ;; 0x10) echo "battery inserted" ;;
	0x00) echo "nothing latched: a reset that did not power-cycle the PMIC" ;;
	none|"") echo "not read" ;;
	*) echo "several bits, which U-Boot counts as unknown" ;;
	esac
}

src_name() {
	case $1 in
	-1) echo "unknown" ;; 0) echo "button" ;; 1) echo "irq" ;; 2) echo "usb, no battery" ;;
	3) echo "charger" ;; 4) echo "battery" ;; *) echo "?" ;;
	esac
}

prune() {	# keep the last $KEEP records in $1
	set -- $(ls -d "$1"/boot-* 2>/dev/null | sort)
	while [ $# -gt $KEEP ]; do rm -rf "$1"; shift; done
}

boot() {
	mkdir -p $D || return
	n=$(( $(cat $D/bootcount 2>/dev/null || echo 0) + 1 ))
	echo $n > $D/bootcount
	R=$(rec $n); P=$(rec $((n - 1)))
	mkdir -p "$R" && echo "$R" > $CUR
	mark=$(arg oakmoss.prev_mark); pwron=$(arg oakmoss.pwron); f0=$(arg oakmoss.f0); src=$(arg oakmoss.src)
	case $f0 in 0x*) [ $((f0 & 8)) = 8 ] && f0="$f0 (bit 3, U-Boot's charging flag, is SET)" ;; esac
	{
		echo "oakMOSS debug record ${R##*/}, written $(now) at uptime $(up) s"
		cat /etc/oakmoss-debug 2>/dev/null
		uname -a
		echo
		echo "== How this boot started (U-Boot)"
		echo "power-on source, PMIC 0x20: $pwron = $(pwron_name "$pwron")"
		echo "power-off status, PMIC 0x21: $(arg oakmoss.pwroff)"
		echo "PMIC 0xf0: $f0"
		echo "U-Boot's decision: source $src ($(src_name "$src")), charge mode $(arg oakmoss.chg)," \
		     "charge-mode check ran $(arg oakmoss.axpinfo), boot-package logo $(arg oakmoss.logo)"
		echo "androidboot.mode=$(arg androidboot.mode)"
		echo
		echo "== How the boot before ended"
		echo "last mark: $mark = $(mark_name "$mark")"
		if [ -f "$P/shutdown.txt" ]; then
			echo "${P##*/}: orderly shutdown recorded ($(sed -n 's/^started: //p' "$P/shutdown.txt"))"
		elif [ -d "$P" ]; then
			echo "${P##*/}: no shutdown recorded: power loss, crash, hang, long press, or a reboot that bypassed init"
		else
			echo "no record of the boot before"
		fi
		echo
		echo "== Kernel command line"; cat /proc/cmdline; echo
		echo "== PMIC registers (AXP2202)"; pmic; echo
		echo "== Power supplies"; supplies
	} 2>&1 | mask > "$R/boot.txt"
	knob /proc/sys/kernel/softlockup_panic 1
	knob /proc/sys/kernel/hung_task_timeout_secs 120
	knob /proc/sys/kernel/hung_task_panic 0
	prune $D
}

to_card() {	# this record, the one before it and the boot log, onto the SD card
	grep -q ' /mnt/SDCARD ' /proc/mounts || return
	mkdir -p $CARD || return
	n=$(cat $D/bootcount)
	cp /usr/magicx/share/oakmoss-debug-README.txt $CARD/README.txt
	mask < /mnt/UDISK/oakmoss-boot.log > $CARD/oakmoss-boot.log 2>/dev/null
	for r in "$(rec $((n - 1)))" "$(rec "$n")"; do
		[ -d "$r" ] && cp -r "$r" $CARD/
	done
	prune $CARD
	sync
}

late() {
	R=$(cat $CUR 2>/dev/null) || return
	sleep 60
	dmesg | mask > "$R/dmesg.txt"
	m=$(arg oakmoss.prev_mark)
	echo "$(up) debug: ${R##*/} recorded, last mark $m ($(mark_name "$m"))" >> /mnt/UDISK/oakmoss-boot.log
	i=0
	until grep -q ' /mnt/SDCARD ' /proc/mounts; do
		i=$((i + 1)); [ $i -gt 60 ] && return
		sleep 5
	done
	to_card
}

shutdown() {
	R=$(cat $CUR 2>/dev/null); [ -n "$R" ] || R=$D/boot-unknown
	mkdir -p "$R"
	{
		echo "started: $(now) at uptime $(up) s"
		echo "an orderly shutdown or reboot: procd is running the K scripts"
		echo
		echo "== PMIC registers (AXP2202)"; pmic; echo
		echo "== Power supplies"; supplies; echo
		echo "== Mounts"; grep -E ' (/|/overlay|/mnt/[^ ]*) ' /proc/mounts; echo
		echo "== Processes"; procs; echo
		echo "== Kernel log, last 300 lines"; dmesg | tail -n 300
	} 2>&1 | mask > "$R/shutdown.txt"
	# A task stuck for 30 s from here on panics, so a hung shutdown reboots and leaves mark 0x63.
	knob /proc/sys/kernel/hung_task_timeout_secs 30
	knob /proc/sys/kernel/hung_task_panic 1
	if grep -q ' /mnt/SDCARD ' /proc/mounts; then
		mkdir -p "$CARD/${R##*/}" && cp "$R/shutdown.txt" "$CARD/${R##*/}/"
	fi
	sync
}

case $1 in
	boot|late|shutdown) "$1" ;;
	*) echo "usage: $0 boot|late|shutdown" >&2; exit 2 ;;
esac
