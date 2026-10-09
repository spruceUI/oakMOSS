#!/bin/sh
# oakMOSS debug records: one per boot of how it started and how the boot before ended.
# Usage: oakmoss-debug.sh boot | late | shutdown   (run by /etc/init.d/oakmoss-debug; off with oakmoss_debug=0)
D=/mnt/UDISK/oakmoss-debug		# small ring on the 3 MB overlay: boot.txt and a short shutdown.txt
CARD=/mnt/SDCARD/oakmoss-debug		# the full records
T=/tmp/oakmoss-debug			# this boot's record until the card is there
KEEP=30
KEEP_UDISK=6

now() { date '+%Y-%m-%d %H:%M:%S'; }
up() { cut -d' ' -f1 /proc/uptime; }
knob() { [ -w "$1" ] && echo "$2" > "$1"; }
name() { printf 'boot-%04d' "$1"; }
card_up() { grep -q ' /mnt/SDCARD ' /proc/mounts; }
# The overlay that holds /mnt/UDISK is 3 MB: nothing goes there with under 1 MB free.
udisk_ok() { [ "$(df -k /overlay 2>/dev/null | tail -n 1 | awk '{ print $(NF - 2) }')" -ge 1024 ] 2>/dev/null; }

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
	""|none) echo "not passed: a U-Boot without the oakMOSS boot arguments" ;;
	0x00000000) echo "empty: the RTC lost power, or the boot before ran an older oakMOSS" ;;
	0x0000000[1-5]) echo "kernel init hand-off stage ${1#0x0000000}: stopped before userland" ;;
	0x00000006) echo "userland started and nothing was marked after: crash, hang or power loss there" ;;
	0x75000001) echo "U-Boot stopped after board init, before booting the kernel" ;;
	0x75000002) echo "U-Boot booted the kernel, which wrote no mark (kernel marks off, or it stopped very early)" ;;
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

prune() {	# prune <dir> <count>: keep the last <count> records
	k=$2
	set -- $(ls -d "$1"/boot-* 2>/dev/null | sort)
	while [ $# -gt "$k" ]; do rm -rf "$1"; shift; done
}

boot() {
	[ "$(fw_printenv -n oakmoss_debug 2>/dev/null)" = 0 ] && return
	mkdir -p $D $T || return
	n=$(( $(cat $D/bootcount 2>/dev/null || echo 0) + 1 ))
	echo $n > $D/bootcount; echo $n > $T/n
	R=$T/$(name $n); P=$D/$(name $((n - 1)))
	mkdir -p "$R"
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
			echo "no record of the boot before on this card"
		fi
		echo
		echo "== Kernel command line"; cat /proc/cmdline; echo
		echo "== PMIC registers (AXP2202)"; pmic; echo
		echo "== Power supplies"; supplies
	} 2>&1 | mask > "$R/boot.txt"
	if udisk_ok; then mkdir -p "$D/${R##*/}" && cp "$R/boot.txt" "$D/${R##*/}/"; fi
	prune $D $KEEP_UDISK
	knob /proc/sys/kernel/softlockup_panic 1
	knob /proc/sys/kernel/hung_task_timeout_secs 120
	knob /proc/sys/kernel/hung_task_panic 0
}

spruce_log() {	# a compact summary where spruce's Bug report task packs logs from (Saves/spruce/*.log)
	[ -d /mnt/SDCARD/Saves/spruce ] || return
	n=$(cat $T/n); r=$CARD/$(name "$n"); s=$r/shutdown.txt
	[ -f "$s" ] || s=$CARD/$(name $((n - 1)))/shutdown.txt
	{
		echo "oakMOSS debug summary, written $(now) at uptime $(up) s; full records: oakmoss-debug/ on this card"
		cat /etc/oakmoss-debug 2>/dev/null
		echo
		echo "== The last 10 boots, newest first"
		i=$n
		while [ $i -gt 0 ] && [ $i -gt $((n - 10)) ]; do
			b=$CARD/$(name $i)/boot.txt
			if [ -f "$b" ]; then
				echo "-- $(name $i)"
				sed -n '/^== How this boot started/,/^== Kernel command line/p' "$b" | grep -v '^== Kernel command line'
				[ -f "${b%/*}/shutdown.txt" ] && echo "its shutdown began $(sed -n 's/^started: //p' "${b%/*}/shutdown.txt")"
			fi
			i=$((i - 1))
		done
		echo
		echo "== This boot: PMIC and power supplies"
		sed -n '/^== PMIC registers/,$p' "$r/boot.txt"
		if [ -f "$s" ]; then
			echo
			echo "== The latest shutdown record (${s%/*})"
			cat "$s"
		fi
		echo
		echo "== This boot: kernel log, last 200 lines"
		dmesg | tail -n 200
	} 2>&1 | mask > /mnt/SDCARD/Saves/spruce/oakmoss-debug.log
}

to_card() {	# this boot's record and the short ones the base card kept, onto the SD card
	card_up && mkdir -p $CARD || return
	cp /usr/magicx/share/oakmoss-debug-README.txt $CARD/README.txt
	mask < /mnt/UDISK/oakmoss-boot.log > $CARD/oakmoss-boot.log 2>/dev/null
	for r in $D/boot-*; do		# what the card lacks: a record (no card at that boot) or its shutdown
		[ -d "$r" ] || continue
		if [ ! -d "$CARD/${r##*/}" ]; then cp -r "$r" $CARD/
		elif [ -f "$r/shutdown.txt" ] && [ ! -f "$CARD/${r##*/}/shutdown.txt" ]; then cp "$r/shutdown.txt" "$CARD/${r##*/}/"
		fi
	done
	cp -r $T/boot-* $CARD/
	prune $CARD $KEEP
	sync
}

late() {
	[ -f $T/n ] || return
	sleep 60
	R=$T/$(name "$(cat $T/n)")
	dmesg | mask > "$R/dmesg.txt"
	m=$(arg oakmoss.prev_mark)
	echo "$(up) debug: ${R##*/} recorded, last mark $m ($(mark_name "$m"))" >> /mnt/UDISK/oakmoss-boot.log
	i=0
	until card_up; do
		i=$((i + 1)); [ $i -gt 60 ] && return
		sleep 5
	done
	to_card
	spruce_log
	sync
}

shutdown() {
	[ -f $T/n ] || return
	R=$T/$(name "$(cat $T/n)")
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
	if udisk_ok && [ -d "$D/${R##*/}" ]; then	# the short form: no process list, a shorter log
		sed -e '/^== Processes/,$d' "$R/shutdown.txt" > "$D/${R##*/}/shutdown.txt"
		{ echo "== Kernel log, last 60 lines"; tail -n 60 "$R/shutdown.txt"; } >> "$D/${R##*/}/shutdown.txt"
	fi
	if card_up; then
		mkdir -p "$CARD/${R##*/}" && cp "$R/shutdown.txt" "$CARD/${R##*/}/"
		spruce_log
	fi
	sync
}

case $1 in
	boot|late|shutdown) "$1" ;;
	*) echo "usage: $0 boot|late|shutdown" >&2; exit 2 ;;
esac
